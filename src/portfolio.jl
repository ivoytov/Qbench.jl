import Base: push!

mutable struct Portfolio
    date::Date
    positions::Dict{Security, Position}
    cash::Position
end

Portfolio(inception::Date, cash) = Portfolio(inception, Dict{Security, Position}(), Position(cash, inception))
Portfolio(cash) = Portfolio(Dates.today(), Position(cash))

Base.broadcastable(x::Portfolio) = Ref(x)
function Base.show(io::IO, p::Portfolio)
    trades = gettrades(p, p.date)
    flow_trades = filter(is_flow, trades)
    divs = reduce(+, value.(filter(t -> t.trade_type == DIVIDEND, trades)), init=0)
    fees = reduce(+, value.(filter(t -> t.trade_type == BORROWFEE, trades)), init=0)
    @printf(io, "%s | %9.0f %6.0f | %6.2f %6.2f %6.2f %6.2f | %4i %4i %4i | %6.0f %6.0f",  p.date, equity(p), pnl(p, closingbell(advancebdays(cal, p.date, -1)), closingbell(p.date)) , grossexposure(p), longexposure(p), shortexposure(p), hedgeexposure(p), length(p.positions), length(trades), length(flow_trades), divs, fees)
end

"Return the DateTime of the closing bell on that date"
closingbell(date::Date) = DateTime(date) + Hour(16)

const TABLE_HEADER = @sprintf("%-10s | %9s %6s | %6s %6s %6s %6s | %4s %4s %4s | %6s %6s",  "DATE", "EQUITY", "P&L", "GROSS", "LONG", "SHORT", "HEDGE", "#POS", "#TRD", "#FLW", "DVD", "FEES")

"Portfolio P&L between dates"
pnl(p::Portfolio, start_dt::DateTime, end_dt::DateTime) = equity(p, end_dt) - equity(p, start_dt)

function max_drawdown(close) 
    trough = argmax((accumulate(max, close) - close) ./ accumulate(max, close))
    peak = argmax(close[begin:trough])
    close[trough] / close[peak] - 1
end

function portfolio_statistics(p::Portfolio, start_dt::Date, end_dt::Date) 
    fa = listbdays(cal, start_dt, end_dt) .|> closingbell .|> day -> equity(p, day)
    daily_returns = diff(log.(fa))
    annualized_return = (exp(sum(daily_returns)) ^ (252/(size(daily_returns,1)-1)) - 1) * 100
    sharpe = mean(daily_returns) / std(daily_returns) * sqrt(252)
    
    annualized_return, sharpe, max_drawdown(fa) * 100
end

"Simple period return (assumes no cash flows)"
period_return(p::Portfolio, start_dt::Date, end_dt::Date) = equity(p, closingbell(end_dt)) / equity(p, closingbell(start_dt)) - 1

annualized_return(p::Portfolio, start_dt::Date, end_dt::Date) = (1 + period_return(p, start_dt, end_dt)) ^ (252/bdayscount(cal, start_dt, end_dt)) - 1


"Returns by year"
returns_by_year(p::Portfolio, start_dt::Date, end_dt::Date) = 
lastdayofyear.(start_dt:Year(1):lastdayofyear(end_dt)) .|> date -> (year(date), period_return(p, max(start_dt, date-Year(1)), min(end_dt, date)))

"Sharpe ratio"
function sharpe(p::Portfolio, start_dt::DateTime, end_dt::DateTime)
end

"Portfolio gross exposure"
grossexposure(p::Portfolio) = longexposure(p) + shortexposure(p)

"Portfolio gross exposure"
netexposure(p::Portfolio) = longexposure(p) - shortexposure(p)

"Returns all of the positions classified as hedges"
gethedges(port::Portfolio) = values(filter(p -> (getgroup(p.second) == "HEDGE") && (sharesowned(p.second) != 0), port.positions))

"Returns all non-hedge single name positions"
activepositions(port::Portfolio) = values(filter(p -> (getgroup(p.second) != "HEDGE") && (sharesowned(p.second) != 0), port.positions))

"Portfolio net liquidation value"
equity(p::Portfolio, dt::DateTime = Dates.now()) = cash(p, dt) + reduce(+, value.(positions(p, dt), dt), init=0.0)
cash(p::Portfolio, dt::DateTime = Dates.now()) = value(p.cash, dt)

shorts(p::Portfolio)::Vector{Position} = [pos for pos in positions(p) if is_short(pos)]
positions(p::Portfolio, dt::DateTime = Dates.now()) = values(filter(p -> sharesowned(p.second, dt) != 0, p.positions))

getposition(p::Portfolio, security::Security) = get(p.positions, security, nothing)

longexposure(p::Portfolio) = reduce(+, filter(>(0), value.(positions(p))), init=0.0) / equity(p)
shortexposure(p::Portfolio) = reduce(-, filter(<(0), value.(positions(p))), init=0.0) / equity(p)
hedgeexposure(p::Portfolio) = reduce(+, value.(gethedges(p)), init=0.0) / equity(p)

gettrades(p::Portfolio, date::Date)::Vector{Trade} = vcat(gettrades.(values(p.positions), DateTime(date), DateTime(date + Dates.Day(1)))...)

const MAX_FEE_RATE = 10.


"""
Adds the trade to the portfolio ledger. Updates the cash balance.
"""
function push!(port::Portfolio, trade::Trade) 
    pos = get!(port.positions, trade.security, Position(trade.security))
    push!(pos, trade)
    push!(port.cash, Trade(-value(trade), trade.datetime))
    return port
end

mark!(port::Portfolio, close::Close) = mark!(port.positions[close.security], close)

"Advances portfolio date forward by 1 business day"
nextday!(port::Portfolio) = port.date = advancebdays(:USNYSE, port.date, 1)

"Creates and completes a market trade necessary to get net exposure to zero"
function hedgebook(port::Portfolio, close, existshares)
    hedgetgt = hedgeexposure(port) - netexposure(port) # mkt value need as % of AUM
    shares = tradeshareqty(hedgetgt, existshares, equity(port), close.close)
    trade_type = gettradetype(shares, existshares)
    return Order(close.datetime, close.security, abs(shares), trade_type, MARKET, close.close, "CEF", "HEDGE")
end


function trade_to_target(port::Portfolio, close::Close, target_exposure, limit = nothing, reason = "HEDGE")
    position = getposition(port, close.security)
    existshares = isnothing(position) ? 0 : sharesowned(position)
    shares = tradeshareqty(target_exposure, existshares, equity(port), close.close)
    shares == 0 && return nothing
    trade_type = gettradetype(shares, existshares)
    trade_date = advancebdays(cal, close.datetime, 1)
    price = isnothing(limit) ? close.close : limit
    order_type = isnothing(limit) ? MARKET : LIMIT
    Order(trade_date, close.security, abs(shares), trade_type, order_type, price, "CEF", reason)
end
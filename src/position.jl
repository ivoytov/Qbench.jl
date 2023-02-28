import Base: push!, ==

struct Position
    security::Security
    trades::Vector{Trade}
    closes::Vector{Close}
end

==(x::Position, y::String) = x.security.ticker == y
==(x::String, y::Position) = y.security.ticker == x

Position(security::Security) = Position(security, Trade[], Close[])
Position(security::Security, close::Close) = Position(security, Trade[], [close])
Position(balance::Number, date::Date) = Position(Security(1, "CASH_USD"), [Trade(balance, closingbell(date))], Close[])

Base.broadcastable(x::Position) = Ref(x)
function cost(position::Position, dt::DateTime=Dates.now()) 
    cost = reduce(+, value.(gettrades(position, START_DATE, dt)), init=0)
    shares = sharesowned(position, dt)
    shares == 0 ? 0 : cost / shares
end

function value(position::Position, dt::DateTime=Dates.now())
    shares = sharesowned(position, dt)
    last_index = findlast(close -> close.datetime <= dt, position.closes)
    close = isnothing(last_index) ? cost(position, dt) : position.closes[last_index].close
    shares * close
end

Base.show(io::IO, x::Position) = @printf io "%-6s value %8.0f shares %6d cost %6.2f close %6.2f" x.security value(x) sharesowned(x) ismissing(cost(x)) ? -1 : cost(x) isempty(x.closes) ? -1 : last(x.closes).close

is_short(p::Position) = sharesowned(p) < 0
function sharesowned(p::Position, dt::DateTime=Dates.now())
    trades = filter(trade -> (trade.datetime <= dt) & !is_flow(trade), p.trades)
    qty = map(trade -> trade.qty * sign(trade.trade_type), trades)
    reduce(+, qty, init=0)
end

getsecurity(position::Position) = position.security

push!(position::Position, trade::Trade) = push!(position.trades, trade)
mark!(position::Position, close::Close) = push!(position.closes, close)

getgroup(p::Position) = (!isempty(p.trades) && !isnothing(p.trades[1].order)) ? p.trades[1].order.reason : ""
gettrades(p::Position, start_dt::DateTime = START_DATE, end_dt::DateTime = Dates.now())::Vector{Trade} = filter(t -> (t.datetime >= start_dt) & (t.datetime <= end_dt), p.trades)
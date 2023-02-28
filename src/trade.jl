const MAX_PCT_OF_VOLUME = PERCENT_OF_ADV # this is different from the similar constant used for probable execution

struct Trade
    order::Union{Order,Nothing}
    datetime::DateTime
    security::Security
    qty::Union{Nothing,Float64}
    trade_type::TradeType
    price::Union{Nothing,Float64}
    value::Union{Nothing,Float64}  #positive = cash outflow for the portfolio. BUYS, BORROWFEES are +; SELLS, DIVS are -
    "Constructs a charge for the daily borrow fee. Value is expected to be negative"
    Trade(borrow::Borrow, value, days=1) = new(nothing, borrow.date, borrow.security, nothing, BORROWFEE, borrow.feerate / 100., -value * borrow.feerate / 100. / 360 * days)
    "Constructs a dividend or payment in lieu. If we are short, pass negative amt to qty"
    Trade(dvd::Dividend, qty) = new(nothing, dvd.ex_date, dvd.security, qty, DIVIDEND, dvd.amount, -qty * dvd.amount)
    Trade(split::Split, qty) = new(nothing, split.date, split.security, round(qty / split.split_from * split.split_to - qty), STOCK_SPLIT, 0, 0)
    Trade(security::Security, qty, trade_type, price, dt::DateTime = Dates.now()) = new(nothing, dt, security, qty, trade_type, price, qty * price * sign(trade_type))
    Trade(cash::Number, dt::DateTime) = new(nothing, dt, Security(1, "CASH_USD"),  abs(cash), cash >= 0 ? DEBIT : CREDIT, 1., cash)
    
    "create a Trade from a Close"
    function Trade(order::Order, clz::Close, remaining=order.qty) 
        order.security != clz.security && error("Security traded doesn't match the close security")
        order.date != Date(clz.datetime) && error("Order date $(order.date) doesn't match the close date $(clz.datetime)")
        (ismissing(clz.volume) || clz.volume == 0) && return nothing
        px = ismissing(clz.vwap) ? clz.close : clz.vwap
        if order.order_type == LIMIT 
            sgn = sign(order.trade_type)
            sgn * px > sgn * order.price && return nothing
        end

        pct = order.order_type == LIMIT ? 1.00 : MAX_PCT_OF_VOLUME
        qty = floor(min(clz.volume * pct, remaining))
        return new(order, clz.datetime, order.security, qty, order.trade_type, px, qty * px * sign(order.trade_type))
    end
end

Base.broadcastable(x::Trade) = Ref(x)
Base.show(io::IO, d::Trade) = print(io, d.security, ':', d.trade_type, ' ', d.qty, '$', d.price, ':', d.datetime, '=', value(d))
is_flow(t::Union{Order, Trade}) = t.trade_type ∈ [DIVIDEND, BORROWFEE]
value(t::Trade) = t.value

function getfills(order::Order, close::Vector{Close})::Vector{Trade}
    out = Trade[]
    remain_qty = order.qty
    for clz in close
        trade = Trade(order, clz, remain_qty)
        if !isnothing(trade)
            push!(out, trade)
            remain_qty -= trade.qty
            remain_qty == 0 && break
        end
    end
    return out
end
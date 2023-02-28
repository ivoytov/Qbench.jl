using Dates

@enum TradeType begin
    BUY = 1
    COVER = 2
    SELL = -1
    SELL_SHORT = -2
    DIVIDEND = 0
    STOCK_SPLIT = 3
    BORROWFEE = 10
    DEBIT = 4
    CREDIT = -4
end

gettradetype(shares, existshares) = shares > 0 ? (existshares >= 0 ? BUY : COVER) : (existshares > 0 ? SELL : SELL_SHORT)

Base.sign(t::TradeType) = sign(Int(t))

@enum OrderType begin
    MARKET
    LIMIT
    VWAP
    VWAP_LIMIT
end

@enum PositionType begin
    LONG = 1
    SHORT = -1
end

struct Order
    date::Date
    security::Security
    qty::UInt
    trade_type::TradeType
    order_type::OrderType
    price::Float64
    strategy::String
    reason::String
end

Base.broadcastable(x::Order) = Ref(x)
Base.show(io::IO, x::Order) = print(io, x.trade_type, ',', x.security, ',', x.qty, '@', x.price,',', x.order_type, '{', round(value(x)),'}')
value(t::Order) = t.qty * t.price * sign(t.trade_type)

const MAX_EXPOSURE = 1.50
const MIN_EXPOSURE = 1.00
strategyexpotarget(universe::Dict) = max(MIN_EXPOSURE, (abs ∘ positionsize ∘ zscore)(universe) / 100. * MAX_EXPOSURE)

const MAX_POS_SIZE = 0.03
"Returns a value between 0.0 and MAX_POS_SIZE which is the equivalent of a 100 (or -100) position size in terms of % of portfolio"
fullpositionexpo(tgts_sum, tgt_exposure=1.0) = min(MAX_POS_SIZE, tgt_exposure / abs(tgts_sum / 100.))

const MIN_POS_SIZE = 0.005
const MIN_TRADE_SIZE = MIN_POS_SIZE / 2.
"""
Calculates how many shares we should be buying or selling today based on existing and target position size and portfolio size
Positive value means shares to buy, negative is shares to sell
"""
function tradeshareqty(target_expo, existing_shares, aum::Float64, price::Float64)::Integer
    if existing_shares == 0
        # this is a new position
        abs(target_expo) < MIN_POS_SIZE && return 0
        return round(target_expo * aum / price, digits=-2)    
    end
    
    # we have an existing position
    existing_expo = existing_shares * price / aum
    abs(target_expo - existing_expo) < MIN_TRADE_SIZE && return 0

    # we are switching directions, exit entirely
    # we are dropping below min position size, exit entirely
    (sign(existing_shares) != sign(target_expo) || abs(target_expo) < MIN_POS_SIZE) && return -existing_shares
        
    round( (target_expo - existing_expo) * aum / price, digits = -2)        
end

const PERCENT_OF_ADV = 0.04
"Returns the expected number of shares that will get filled"
probable_execution(order::Order, adv) = round(Int, min(PERCENT_OF_ADV * adv / order.price, order.qty))

"Calculate the market value of hedge needed to offset probable executions of orders"
hedgeneed(orders::Vector{Pair{Order, Float64}}) = reduce(-, [sign(order.trade_type) * order.price * probable_execution(order, adv) for (order, adv) in orders], init=0.0)

"Security of the order"
getsecurity(order::Order) = order.security
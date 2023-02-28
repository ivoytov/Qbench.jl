import Base: +

struct Dividend
    security::Security
    ex_date::Date
    payment_date::Union{Date, Nothing}
    amount::Float64
    type::String
    declaration_date::Union{Date,Nothing}
    record_date::Union{Date, Nothing}
    frequency::Integer
end

Base.broadcastable(x::Dividend) = Ref(x)
Base.show(io::IO, d::Dividend) = print(io, '$', d.amount, ':', d.ex_date)
+(x::Dividend, y::Dividend) = Dividend(x.security, x.ex_date, nothing, x.amount + y.amount, x.type, nothing, nothing, x.frequency)

getsecurity(dividend::Dividend) = dividend.security
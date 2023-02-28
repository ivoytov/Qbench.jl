import Base: ==

struct Security
    id::Integer
    ticker::String
    cusip::Union{String, Nothing}
    conid::Union{Integer, Nothing}
    currency::Union{String, Nothing}
    isin::Union{String, Nothing}
    composite_figi::Union{String, Nothing}
end

==(x::Security, y::String) = x.ticker == y
==(x::String, y::Security) = y.ticker == x

Base.broadcastable(x::Security) = Ref(x)
Base.show(io::IO, x::Security) = print(io, x.ticker)

Security(id, ticker) = Security(id, ticker, nothing)
Security(id, ticker, nothing) = Security(id, ticker, nothing, nothing, nothing, nothing, nothing)
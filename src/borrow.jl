import Base: ==
using Dates

struct Borrow
    security::Security
    date::Date
    rebaterate::Float64
    feerate::Float64
    available::Integer
end

Base.broadcastable(x::Borrow) = Ref(x)
Base.show(io::IO, b::Borrow) = print(io, round(b.feerate; digits=2))

==(x::Borrow, y::Float64) = x.feerate == y
Base.:>(x::Borrow, y::Float64) = x.feerate > y
Base.:<(x::Borrow, y::Float64) = x.feerate < y
Base.:+(x::Float64, y::Borrow) = x + y.feerate
Base.:/(x::Borrow, y::Int64) = x.feerate / y

==(x::Borrow, y::Borrow) = x.feerate == y.feerate
Base.:>(x::Borrow, y::Borrow) = x.feerate > y.feerate
Base.:<(x::Borrow, y::Borrow) = x.feerate < y.feerate
Base.:+(x::Borrow, y::Borrow) = x.feerate + y.feerate
Base.isless(x::Borrow, y::Borrow) = x.feerate < y.feerate

getsecurity(borrow::Borrow) = borrow.security
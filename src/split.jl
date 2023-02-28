struct Split
    security::Security
    date::Date
    split_from::Integer
    split_to::Integer
end

Base.broadcastable(x::Split) = Ref(x)
Base.show(io::IO, s::Split) = @printf io "%-4s from: %3d to: %3d on: %s" s.security.ticker s.split_from s.split_to s.date
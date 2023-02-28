struct Close
    security::Security
    datetime::DateTime
    open::Union{Float64, Missing}
    high::Union{Float64, Missing}
    low::Union{Float64, Missing}
    close::Union{Float64, Missing}
    vwap::Union{Float64, Missing}
    volume::Union{Integer, Missing}
    source::Union{String, Missing}
end

Close(security, datetime, close, volume) = Close(security, datetime, missing, missing, missing, close, missing, volume, missing)

Base.broadcastable(x::Close) = Ref(x)
Base.show(io::IO, d::Close) = print(io, '$', d.close, ':', d.datetime)

daily_value(c::Close) = (!ismissing(c.volume) ? c.volume : 0) * (!ismissing(c.vwap) ? c.vwap : !ismissing(c.close) ? c.close : 0)
adv(hist::Vector{Close}, n::Integer=20) = mean(daily_value.(hist[end-min(n, length(hist)-1):end]))
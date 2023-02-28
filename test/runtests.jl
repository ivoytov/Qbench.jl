using Qbench
using Test, Dates, Statistics, BusinessDays

@testset "Qbench.jl" begin
    stock = Security(1, "ABC")
    
    @testset "Make hedge" begin
        # make some nice fake orders for 100, -200, -300 shares at $10
        orders = [Order(Dates.today(), Security(i, x, nothing), i * 100, t, Qbench.LIMIT, 10., "strategy", "reason") 
        for (i, (x,t)) in enumerate(zip(["ABC","DEF","GHI"], [Qbench.BUY, Qbench.SELL_SHORT, Qbench.SELL]))]
        advs = [10e10, 10e10, 2500 * 10] # last order should get cut back to 100
        @test probable_execution(orders[3], advs[3]) == 100

        @test hedgeneed([order => adv for (order, adv) in zip(orders, advs)]) ≈ -(-100 * 10. - 200 * 10. + 100 * 10.)
    end
    
    @testset "Trade execution" begin
        sec = Security(1, "ABC", nothing)
        close = Close(sec, Dates.today(), missing, missing, missing, 10.00, missing, 10000, "Yahoo")

        @test Trade(Order(Dates.today(), sec, 100, Qbench.BUY, Qbench.MARKET, 11, "strategy", "reason"), close).qty == 100
        @test Trade(Order(Dates.today(), sec, 100, Qbench.BUY, Qbench.MARKET, 10, "strategy", "reason"), close).price ≈ 10.00
        
        @test Trade(Order(Dates.today(), sec, 10000, Qbench.SELL, Qbench.MARKET, 11, "strategy", "reason"), close).qty ≈ .04 * 10000

        @test isnothing(Trade(Order(Dates.today(), sec, 100, Qbench.COVER, Qbench.LIMIT, 9, "strategy", "reason"), close))

        @test Trade(Order(Dates.today(), sec, 100, Qbench.COVER, Qbench.LIMIT, 11, "strategy", "reason"), close).price ≈ 10.00

        @test Trade(Order(Dates.today(), sec, 100, Qbench.SELL, Qbench.LIMIT, 9, "strategy", "reason"), close).price ≈ 10.00
        @test isnothing(Trade(Order(Dates.today(), sec, 100, Qbench.SELL_SHORT, Qbench.LIMIT, 11, "strategy", "reason"), close))
    end
    
    @testset "Position" begin
        sec = Security(1, "ABC", nothing)
        pos = Position(sec)
        @test value(pos) == 0
        trade₁ = Trade(sec, 100, Qbench.BUY, 10)
        trade₂ = Trade(sec, 50, Qbench.SELL, 12)
        push!(pos, trade₁)
        @test cost(pos) == 10.
        push!(pos, trade₂)
        @test cost(pos) == 8.

        close = Close(sec, Dates.today(), missing, missing, missing, 11, missing, missing, "Yahoo")
        pos = Position(sec, close)
        
        @test value(trade₁) ≈ 1000
        @test value(trade₂) ≈ -600
        push!(pos, trade₁)
        push!(pos, trade₂)
        @test value(pos) ≈ 550 
        @test sharesowned(pos) == 50

        split = Split(sec, Dates.today(), 5, 6)
        push!(pos, Trade(split, sharesowned(pos)))
        @test sharesowned(pos) == 60
    end

    @testset "Portfolio" begin
        start_date = advancebdays(:USNYSE, Date(2020,1,1), 0)
        port = Qbench.Portfolio(start_date,100000)
        @test equity(port) ≈ 100000
        @test longexposure(port) == 0
        @test shortexposure(port) == 0
        
        sec₁ = Security(1, "ABC", nothing)
        close = Close(sec₁, start_date, missing, missing, missing, 10, missing, missing, "Yahoo")
        trade₁ = Trade(sec₁, 100, Qbench.BUY, 10, DateTime(start_date))
        push!(port, trade₁)
        @test equity(port) ≈ 100000
        mark!(port, close)
        @test longexposure(port) ≈ .01
        @test shortexposure(port) ≈ 0.

        sec = Security(2, "DEF", nothing)
        close = Close(sec, start_date, missing, missing, missing, 10, missing, missing, "Yahoo")
        fee = Borrow(sec, start_date, -10., 10., 10000)
        trade = Trade(sec, 200, Qbench.SELL_SHORT, 10, DateTime(start_date))
        push!(port, trade)
        @test sharesowned(getposition(port, sec₁)) == 100
        @test sharesowned(getposition(port, sec)) == -200
        mark!(port, close)
        @test longexposure(port) ≈ .01
        @test shortexposure(port) ≈ 0.02
        @test grossexposure(port) ≈ .03
        @test netexposure(port) ≈ -.01

        cash1 = cash(port)
        push!.(port,  Trade.([fee], value.(shorts(port)), 1))
        @test cash(port) - cash1 ≈ -2000 * .1 / 360

        next_day = advancebdays(:USNYSE, start_date, 1) 
        dvds = [Dividend(sec₁, next_day, nothing, 2., "SD", nothing, nothing, 12), Dividend(sec, next_day, nothing, 0.5, "SD", nothing, nothing, 12)]
        splits = Dict(sec₁ => Split(sec₁, next_day, 1, 2), sec => Split(sec, next_day, 2,1))

        cash1 = cash(port)
        equity1 = equity(port)
        
        nextday!(port)
        @test port.date > start_date

        eod = closingbell(port.date)
        dvds = map(dvd -> Trade(dvd, sharesowned(getposition(port, getsecurity(dvd)), eod)), dvds)
        push!.(port, dvds)

        δ = 2 * 100 - 0.5 * 200 
        @test cash(port) - cash1 == δ
        @test equity(port) - equity1 == δ
        @test pnl(port, closingbell(start_date), closingbell(next_day)) ≈ δ
        @test annualized_return(port, start_date, next_day) ≈ (1 + δ / equity1)^ 252 - 1
        @test period_return(port, start_date, next_day) ≈ δ / equity1
        @test all(returns_by_year(port, start_date, next_day)[1] .≈ (year(start_date), δ / equity1))
        a = [3, 8, 7, 15]
        b = [10, 9, 8, 7, 8, 9, 10]
        c = [4, 2, 4, 8, 10, 9, 8, 7, 8, 9, 10]
        @test max_drawdown(a) ≈ -1/8
        @test max_drawdown(b) ≈ -.30
        @test max_drawdown(c) ≈ -.50

        cash1 = cash(port)
        equity1 = equity(port)
        for position in positions(port)
            !haskey(splits, getsecurity(position)) && continue
            shrs = sharesowned(position, eod)
            push!(port, Trade(splits[getsecurity(position)], shrs)) 
        end
        @test cash(port) == cash1  # test no change in cash
        @test sharesowned(getposition(port, sec₁)) == 200
        @test sharesowned(getposition(port, sec)) == -100

        close = Close(sec, Dates.today(), missing, missing, missing, 20, missing, missing, "Yahoo")
        mark!(port, close)
        close₁ = Close(sec₁, Dates.today(), missing, missing, missing, 5, missing, missing, "Yahoo")
        mark!(port, close₁)

        @test equity(port) == equity1 # test no change in equity

        etf_close = Close(Security(3, "HYG", nothing), Dates.now(), 5., 5000)
    end
end

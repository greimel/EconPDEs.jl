##############################################################################
##
## Non Linear solver using Pseudo-Transient Continuation Method
##
##############################################################################

# Implicit time step
function implicit_timestep(G!, ypost, Δ; is_algebraic = fill(false, size(ypost)...), iterations = 100, verbose = true, method = :newton, autodiff = :forward, maxdist = sqrt(eps()), J0c = (nothing, nothing), y̲ = fill(-Inf, length(ypost)), ȳ = fill(Inf, length(ypost)), reformulation = :smooth)
    G_helper!(ydot, y) = (G!(ydot, y) ; ydot .-= .!is_algebraic .* (ypost .- y) ./ Δ)
    J0, colorvec = J0c
    if J0 == nothing
        result = nlsolve(G_helper!, ypost; iterations = iterations, show_trace = verbose, ftol = maxdist, method = method, autodiff = autodiff)
    else
        if autodiff == :forward
            jac_cache = ForwardColorJacCache(G_helper!, deepcopy(ypost); colorvec = colorvec, sparsity = J0)
            j_helper! = (J, y) -> forwarddiff_color_jacobian!(J, G_helper!, y, jac_cache)
        else
            j_helper! = (J, y) -> finite_difference_jacobian!(J, G_helper!, y; colorvec = colorvec)
        end
        if any(y̲ .!= -Inf) || any(ȳ .!= Inf)
            # using mcpsolve if lower/upper bounds are given
            result = mcpsolve(OnceDifferentiable(G_helper!, j_helper!, deepcopy(ypost), deepcopy(ypost), J0), y̲, ȳ, ypost; iterations = iterations, show_trace = verbose, ftol = maxdist, method = method, reformulation = reformulation)
        else
            result = nlsolve(OnceDifferentiable(G_helper!, j_helper!, deepcopy(ypost), deepcopy(ypost), J0), ypost; iterations = iterations, show_trace = verbose, ftol = maxdist, method = method)
        end
    end
    return result.zero, result.residual_norm
end

# Solve for steady state
function finiteschemesolve(G!, y0; Δ = 1.0, is_algebraic = fill(false, size(y0)...), iterations = 100, inner_iterations = 10, verbose = true, inner_verbose = false, method = :newton, autodiff = :forward, maxdist = sqrt(eps()), scale = 10.0, J0c = (nothing, nothing), minΔ = 1e-9, y̲ = fill(-Inf, length(y0)), ȳ = fill(Inf, length(y0)), reformulation = :smooth)
    ypost = y0
    ydot = zero(y0)
    G!(ydot, ypost)
    residual_norm = norm(ydot) / length(ydot)
    isnan(residual_norm) && throw("G! returns NaN with the initial value")
    if Δ == Inf
        ypost, residual_norm = implicit_timestep(G!, y0, Δ; is_algebraic = is_algebraic, verbose = verbose, iterations = iterations,  method = method, autodiff = autodiff, maxdist = maxdist, J0c = J0c, y̲ = y̲, ȳ = ȳ)
    else
        coef = 1.0
        oldresidual_norm = residual_norm
        iter = 0
        if verbose
            @printf "Iter   TimeStep   Residual\n"
            @printf "---- ---------- ----------\n"
        end
        while (iter < iterations) & (Δ >= minΔ) & (residual_norm > maxdist)
            iter += 1
            y, nlresidual_norm = implicit_timestep(G!, ypost, Δ; is_algebraic = is_algebraic, verbose = inner_verbose, iterations = inner_iterations, method = method, autodiff = autodiff, maxdist = maxdist, J0c = J0c, y̲ = y̲, ȳ = ȳ, reformulation = reformulation)
            G!(ydot, y)
            if any(y̲ .!= -Inf) || any(ȳ .!= Inf)
                mask = y̲ .+ eps() .<= y .<= ȳ .- eps() # only unconstrained ydot is relevant for residual_norm calculation
                residual_norm, oldresidual_norm = norm(ydot .* (mask))/sum(mask), residual_norm
            else
                residual_norm, oldresidual_norm = norm(ydot) / length(ydot), residual_norm
            end
            residual_norm = isnan(residual_norm) ? Inf : residual_norm
            if nlresidual_norm <= maxdist
                # if the implicit time step is correctly solved
                if verbose
                    @printf "%4d %8.4e %8.4e\n" iter Δ residual_norm
                end
                coef = (residual_norm <= oldresidual_norm) ? scale * coef : 1.0
                Δ = Δ * coef * oldresidual_norm / residual_norm
                ypost, y = y, ypost
            else
                # verbose && @show iter, Δ, NaN
                # if the implict time step is not solved
                # revert and diminish the time step
                coef = 1.0
                Δ = Δ / 10
                residual_norm = oldresidual_norm
            end
        end
    end
    verbose && ((residual_norm > maxdist) | (Δ < minΔ)) && @warn "Iteration did not converge"
    return ypost, residual_norm
end






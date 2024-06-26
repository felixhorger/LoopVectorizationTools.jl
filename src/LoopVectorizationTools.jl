
module LoopVectorizationTools

	using LoopVectorization
	using Base.Cartesian

	export decomplexify, recomplexify, turbo_block_copyto!, turbo_wipe!, turbo_multiply!


	# Working with complex arrays
	@inline function decomplexify(a::AbstractArray{C}) where C <: Complex
		reinterpret(reshape, real(C), a)
	end
	@inline decomplexify(a::AbstractArray{<: Real}) = a

	@inline function recomplexify(a::AbstractArray{R, N}) where {R <: Real, N}
		@assert N > 1
		reinterpret(reshape, Complex{R}, a)
	end

	# Copying a block of a multi-dimensional array
	@generated function turbo_block_copyto!(
		dest::AbstractArray{T, N},
		src::AbstractArray{T, N},
		shape::NTuple{N, Int64},
		offset_dest::NTuple{N, Int64},
		offset_src::NTuple{N, Int64}
	) where {T <: Real, N}
		loops = quote
			@nloops(
				$N, i,
				d -> 1:i_max_d,
				d -> begin
					j_dest_d = i_d + k_dest_d
					j_src_d = i_d + k_src_d
				end,
				begin
					(@nref $N dest j_dest) = @nref $N src j_src
				end
			)
		end
		loops_expanded = macroexpand(LoopVectorizationTools, loops)
		return quote
			@assert all(shape .> 0)
			for (arr, off) in ((dest, offset_dest), (src, offset_src))
				@assert all(0 .< off .+ shape .≤ size(arr))
				@assert all(0 .≤ off .≤ size(arr))
			end
			@nextract $N k_dest offset_dest
			@nextract $N k_src offset_src
			@nexprs $N d -> i_max_d = shape[d]
			$(Expr(:macrocall, Symbol("@tturbo"), "", loops_expanded.args[2].args[2]))
			return dest
		end
	end
	# Older version with CartesianIndices, left here as inspiration
	#function block_copyto!(
	#	dest::AbstractArray{T, N},
	#	src::AbstractArray{T, N},
	#	idx::NTuple{D, UnitRange{Int64}},
	#	offset::NTuple{D, Int64}
	#) where {T <: Number, N, D}
	#	other_shape = size(dest)[D+1:N]
	#	@assert other_shape == size(src)[D+1:N]
	#	for K in CartesianIndices(other_shape)
	#		for I in CartesianIndices(idx)
	#			J = CartesianIndex(Tuple(I) .- offset)
	#			dest[I, K] = src[J, K]
	#		end
	#	end
	#	return dest
	#end

	function turbo_wipe!(a::AbstractArray{T, N}) where {T <: Real, N}
		@tturbo for i = 1:length(a)
			a[i] = 0
		end
		return a
	end
	function turbo_wipe!(a::AbstractArray{T, N}) where {T <: Complex, N}
		ad = decomplexify(a)
		turbo_wipe!(ad)
		return a
	end

	@generated function turbo_multiply!(
		x::AbstractArray{<: Real},
		y::Real;
		num_threads::Val{NT}=Val(Threads.nthreads())
	) where NT
		quote
			@tturbo thread=$NT for i in 1:length(x)
				x[i] *= y
			end
			return x
		end
	end

end


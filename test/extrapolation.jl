using FemMesh
using Base.Test

print_with_color(:cyan, "\nShape extrapolation\n")

for shape in ALL_SHAPES
    println("shape : ", shape.name)
    C = shape.nat_coords
    n = shape.npoints
    ndim = shape.ndim

    # calculate nodal values using a linear scalar function
    V = zeros(n)
    for i=1:n
        x, y, z = [C[i,:]; 0.0; 0.0]
        V[i] = x+y+z+1.0
    end

    # Analize for each number of integration points
    for (nip, Cip) in shape.quadrature
        # Cases with too few ip points for a linear field
        nip <=1 && continue 
        (nip ==2 && shape.basic_shape == WED6) && continue 

        # Exception
        #(nip ==18 && shape == WED15) && continue  # WED15 does not work with nip=18 !

        # Calculate values at ips
        println("  nip = ", nip)
        P = zeros(nip)
        for i=1:nip
            x, y, z = [ Cip[i,:]; 0.0; 0.0 ]
            P[i] = x+y+z+1.0
        end

        E  = extrapolator(shape, nip)
        VV = E*P

        #display([V VV V-VV ])
        @test V ≈ VV atol=1e-10
    end
    println("  ok")
end



mutable struct VTK_unstructured_grid
    title::String
    points::Array{Float64,2}
    cells ::Array{Array{Int64,1},1}
    cell_types::Array{Int64,1}
    point_scalar_data::Dict{String,Array}
    cell_scalar_data ::Dict{String,Array}
    point_vector_data::Dict{String,Array}
    version::String
    function VTK_unstructured_grid(title, points, cells, cell_types; point_scalar_data=Dict(), cell_scalar_data=Dict(), point_vector_data=Dict())
        return new(title, points, cells, cell_types, point_scalar_data, cell_scalar_data, point_vector_data, "3.0")
    end
end

function save_vtk(vtk_data::VTK_unstructured_grid, filename::String)
    # Saves a VTK_unstructured_grid
    npoints = size(vtk_data.points, 1)
    ncells = length(vtk_data.cells)

    # Number of total connectivities
    nconns = 0
    for cell in vtk_data.cells
        nconns += 1 + length(cell)
    end


    # Open filename
    f = open(filename, "w")

    println(f, "# vtk DataFile Version $(vtk_data.version)")
    println(f, vtk_data.title)
    println(f, "ASCII")
    println(f, "DATASET UNSTRUCTURED_GRID")
    println(f, "")
    println(f, "POINTS ", npoints, " float64")

    # Write nodes
    for i=1:npoints
        @printf f "%23.15e %23.15e %23.15e \n" vtk_data.points[i,1] vtk_data.points[i,2] vtk_data.points[i,3]
    end
    println(f)

    # Write connectivities
    println(f, "CELLS ", ncells, " ", nconns)
    for cell in vtk_data.cells
        print(f, length(cell), " ")
        for id in cell
            print(f, id-1, " ")
        end
        println(f)
    end
    println(f)

    # Write elem types
    println(f, "CELL_TYPES ", ncells)
    for ty in vtk_data.cell_types
        println(f, ty)
    end
    println(f)

    has_point_scalar_data = !isempty(vtk_data.point_scalar_data)
    has_point_vector_data = !isempty(vtk_data.point_vector_data)
    has_point_data = has_point_scalar_data || has_point_vector_data
    has_cell_data  = !isempty(vtk_data.cell_scalar_data)

    # Write point data
    if has_point_data
        println(f, "POINT_DATA ", npoints)
        # Write scalar data
        if has_point_vector_data
            for (field,D) in vtk_data.point_vector_data
                isempty(D) && continue
                dtype = eltype(D)<:Integer ? "int" : "float64"
                println(f, "VECTORS ", "$field $dtype")
                for i=1:npoints
                    @printf f "%23.15e %23.15e %23.15e \n" D[i,1] D[i,2] D[i,3]
                end
            end
        end
        # Write vector data
        if has_point_scalar_data
            for (field,D) in vtk_data.point_scalar_data
                isempty(D) && continue
                dtype = eltype(D)<:Integer ? "int" : "float64"
                println(f, "SCALARS $field $dtype 1")
                println(f, "LOOKUP_TABLE default")
                if dtype=="float64"
                    for i=1:npoints
                        @printf f "%23.10e" D[i]
                    end
                else
                    for i=1:npoints
                        @printf f "%10d" D[i]
                    end
                end
                println(f)
            end
        end
    end

    # Write cell data
    if has_cell_data
        println(f, "CELL_DATA ", ncells)
        for (field,D) in vtk_data.cell_scalar_data
            isempty(D) && continue
            dtype = eltype(D)<:Integer ? "int" : "float64"
            println(f, "SCALARS $field $dtype 1")
            println(f, "LOOKUP_TABLE default")
            if dtype=="float64"
                for i=1:ncells
                    @printf f "%23.10e" D[i]
                end
            else
                for i=1:ncells
                    @printf f "%10d" D[i]
                end
            end
            println(f)
        end
    end

    close(f) 

    return nothing
end

function read_VTK_unstructured_grid(filename::String)
    file = open(filename)

    # read nodal information
    alltext = readstring(filename)
    data    = split(alltext)

    # read header
    idx  = 1
    while data[idx] != "DATASET"
        idx += 1
    end
    idx += 1

    gridtype = data[idx]
    gridtype == "UNSTRUCTURED_GRID" || error("load_VTK_unstructured_grid: this reader only support files of VTK UNSTRUCTURED_GRID")

    # read number of points
    while data[idx] != "POINTS"
        idx += 1
    end
    npoints = parse(data[idx+1])
    idx += 3

    # read points
    points = zeros(npoints,3)
    for i=1:npoints
        points[i,1] = parse(Float64, data[idx])
        points[i,2] = parse(Float64, data[idx+1])
        points[i,3] = parse(Float64, data[idx+2])
        idx += 3
    end

    # read number of cells
    while data[idx] != "CELLS"
        idx += 1
    end
    ncells = parse(data[idx+1])
    ncdata = parse(data[idx+2])
    idx += 3

    # read cells connectivities
    cells = Array{Int,1}[]
    for i=1:ncells
        npoints = parse(data[idx])
        idx += 1
        conn = Int[]
        for j=1:npoints
            id = parse(data[idx]) + 1
            push!(conn, id)
            idx  += 1
        end
        push!(cells, conn)
    end

    # read type of cells
    while data[idx] != "CELL_TYPES"
        idx += 1
    end
    idx += 2

    cell_types = Int[]
    for i=1:ncells
        vtk_shape = VTKCellType(parse(data[idx]))
        push!(cell_types, vtk_shape)
        idx  += 1
    end

    # read data
    # TODO

    # end of reading
    close(file)

    vtk_data = VTK_unstructured_grid("VTK unstructured grid", points, cells, cell_types)
    return vtk_data
end

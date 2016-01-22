##############################################################################
#    FemLab - Finite Element Library                                         #
#    Copyright (C) 2014 Raul Durand <raul.durand at gmail.com>               #
#                                                                            #
#    This file is part of FemLab.                                            #
#                                                                            #
#    FemLab is free software: you can redistribute it and/or modify          #
#    it under the terms of the GNU General Public License as published by    #
#    the Free Software Foundation, either version 3 of the License, or       #
#    any later version.                                                      #
#                                                                            #
#    FemLab is distributed in the hope that it will be useful,               #
#    but WITHOUT ANY WARRANTY; without even the implied warranty of          #
#    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the           #
#    GNU General Public License for more details.                            #
#                                                                            #
#    You should have received a copy of the GNU General Public License       #
#    along with FemLab.  If not, see <http://www.gnu.org/licenses/>.         #
##############################################################################

export Mesh
export copy, move
export update!, quality!, generate_mesh, save, loadmesh
export get_surface, get_neighbors

include("entities.jl")
include("delaunay.jl")


### Type Mesh
"""
`Mesh()` constructs an unitialized mesh object to be used in finite element analyses.
It contains geometric fields as: points, cells, faces, edges, ndim, quality, etc.
"""
type Mesh
    points ::Array{Point,1}
    cells  ::Array{Cell,1}
    faces  ::Array{Cell,1}
    edges  ::Array{Cell,1}
    bpoints::Dict{UInt64,Point}
    ndim   ::Int
    bins   ::Bins
    quality::Float64
    qmin   ::Float64 

    function Mesh()
        this = new()
        this.points = []
        this.bpoints = Dict{UInt64, Point}()
        this.cells  = []
        this.faces  = []
        this.edges  = []
        this.ndim   = 0
        this.bins   = Bins()
        this.quality = 0.0
        this.qmin    = 0.0
        return this
    end
end

include("block.jl")
include("operators.jl")

function get_surface(cells::Array{Cell,1})
    surf_dict = Dict{UInt64, Cell}()

    # Get only unique faces. If dup, original and dup are deleted
    for cell in cells
        for face in get_faces(cell)
            #conns = [ pt.id for pt in face.points ]
            #hs = hash(conns)
            hs = hash(face)
            if haskey(surf_dict, hs)
                delete!(surf_dict, hs)
            else
                surf_dict[hs] = face
            end
        end
    end

    return [ face for face in values(surf_dict) ]
end

function get_edges(surf_cells::Array{Cell,1})
    edges_dict = Dict{UInt64, Cell}()

    # Get only unique edges
    for cell in surf_cells
        for edge in get_faces(cell)
            edge.ocell = cell.ocell
            edges_dict[hash(edge)] = edge
        end
    end

    return [ edge for edge in values(edges_dict) ] 
end

# Return a list of neighbors for each cell
function get_neighbors(cells::Array{Cell,1})
    faces_dict = Dict{UInt64, Cell}()
    neighbors = [ Cell[] for i=1:length(cells) ]

    # Get cell faces. If dup, original and dup are deleted but neigh info saved
    for cell in cells
        for face in get_faces(cell)
            hs = hash(face)
            other = get(faces_dict, hs, nothing)
            if other == nothing
                faces_dict[hs] = face
            else
                push!(neighbors[face.ocell.id], other.ocell)
                push!(neighbors[other.ocell.id], face.ocell)
                delete!(faces_dict, hs)
            end
        end
    end

    return neighbors

end

# TESTING
function get_surface_alt(cells::Array{Cell,1})
    # Actually slower....
    # Get all points
    pointsd = Dict{UInt64, Point}()
    for cell in cells
        for point in cell.points
            pointsd[hash(point)] = point
        end
    end
    points = values(pointsd)

    # Get incidence matrix (shares) (fast)
    np = length(points)
    N = [ Cell[] for i=1:np]
    for cell in cells
        for pt in cell.points
            push!(N[pt.id], cell)
        end
    end

    @show 1

    # Get matrix of cells faces
    F = [ get_faces(cell) for cell in cells]
    nc = length(cells)
    #CF = Array(Array{Array{Int64,1},1}, nc)
    CF = Array(Array{UInt64,1}, nc)
    for cell in cells # fast
        #CF[cell.id] = [ sort([pt.id for pt in face.points]) for face in F[cell.id]]
        CF[cell.id] = [ hash(face) for face in F[cell.id]]
    end
    @show 2

    # Get cells boundary flag matrix
    CB = [ trues(length(CF[cell.id])) for cell in cells]
    for cell in cells
        for (i,fcon) in enumerate(CF[cell.id])
            for pid in fcon
                for cl in N[pid]
                    if cl.id == cell.id; continue end
                    if fcon in CF[cl.id]
                        CB[cell.id][i] = false
                    end
                end
            end
        end
    end
    @show 3

    # Get list of boundary faces (almost fast)
    facets = Cell[]
    for cell in cells
        for (i,face) in enumerate(F[cell.id])
            if CB[cell.id][i]
                push!(facets, face)
            end
        end
    end
    return facets
end

# Updates numbering, faces and edges in a Mesh object
function update!(mesh::Mesh; verbose::Bool=false, genfacets::Bool=true, genedges::Bool=false)

    # Get ndim
    ndim = 2
    for point in mesh.points
        if point.z != 0.0; ndim = 3; break end
    end
    mesh.ndim = ndim
    
    # Numberig nodes
    for (i,p) in enumerate(mesh.points) p.id = i end

    # Numberig cells 
    for (i,c) in enumerate(mesh.cells ) 
        c.id = i; 
        c.ndim=ndim; 
    end

    # Facets
    if genfacets
        verbose && print("  finding faces...\r")
        mesh.faces = get_surface(mesh.cells)
    end

    # Edges
    if genedges && ndim==3
        verbose && print("  finding edges...\r")
        mesh.edges = get_edges(mesh.faces)
    end


    return nothing
end

# Mesh quality
function quality!(mesh::Mesh)
    Q = [ cell_quality(c) for c in mesh.cells]
    mesh.quality = sum(Q)/length(mesh.cells)
    mesh.qmin    = minimum(Q)
end


"""
Generates a mesh based on an array of geometry blocks:
```
generate_mesh(blocks, [verbose=true,] [genfacets=true,] [genedges=false,] [initial_mesh=nothing]) -> mesh_object
```
"""
function generate_mesh(blocks::Array; verbose::Bool=true, genfacets::Bool=true, genedges::Bool=false, initial_mesh=nothing)
    nblocks = length(blocks)
    if verbose
        println(BOLD, CYAN, "Mesh generation:", DEFAULT)
        println("  analyzing $nblocks block(s)") 
    end

    mesh = initial_mesh==nothing? Mesh(): initial_mesh

    # Split blocks
    for (i,b) in enumerate(blocks)
        b.id = i
        split_block(b, mesh)
        verbose && print("  spliting block ",i,"...\r")
    end

    # Updates numbering, qualitu, facets and edges
    update!(mesh, verbose=verbose, genfacets=genfacets, genedges=genedges)

    if verbose
        npoints = length(mesh.points)
        ncells  = length(mesh.cells)
        nfaces  = length(mesh.faces)
        nedges  = length(mesh.edges)
        println("  ", mesh.ndim, "d found             ")
        @printf "  %5d points obtained\n" npoints
        @printf "  %5d cells obtained\n" ncells
        if genfacets
            @printf "  %5d faces obtained\n" nfaces
        end
        if genedges
            @printf "  %5d surface edges obtained\n" nedges
        end
        icount = 0
        for block in blocks
            if typeof(block) == BlockInset; icount += block.icount end
        end
        if icount>0
            @printf "  %5d intersections found\n" icount
        end
    end

    verbose && println("  done.")

    return mesh
end

"""
Generates a mesh object based on a comma separated list of block objects:
```
generate_mesh(blocks..., [verbose=true,] [genfacets=true,] [genedges=false,] [initial_mesh=nothing]) -> mesh_object
```
"""
function generate_mesh(blocks::Union{Block, Array}...; verbose::Bool=true, genfacets::Bool=true, genedges::Bool=false)
    flat = []
    for bl in blocks
        if isa(bl, Block)
            push!(flat, bl)
        else
            append!(flat, bl)
        end
    end
    generate_mesh(flat, verbose=verbose, genfacets=genfacets, genedges=genedges)
end

"""
Generates a mesh object based on an initial mesh and a comma separated list of block objects:
```
generate_mesh(initial_mesh, blocks..., [verbose=true,] [genfacets=true,] [genedges=false,] [initial_mesh=nothing]) -> mesh_object
```
"""
function generate_mesh(initial_mesh::Mesh, blocks::Block...; verbose::Bool=true, genfacets::Bool=true, genedges::Bool=false)
    generate_mesh([blocks...], verbose=verbose, genfacets=genfacets, genedges=genedges, initial_mesh=initial_mesh)
end


#precompile(generate_mesh, (Array,))
#if VERSION >= v"0.4.0-dev+6521" 
    #precompile(generate_mesh, (Block,))
    #precompile(generate_mesh, (Array,))
#end


"""
Saves a mesh object into a file in VTK legacy format:
```
save(mesh, filename, [verbose=true])
```
"""
function save(mesh::Mesh, filename::AbstractString; verbose::Bool=true)
    # Saves the mesh information in vtk format

    npoints = length(mesh.points)
    ncells  = length(mesh.cells)

    ndata = 0
    for cell in mesh.cells
        ndata += 1 + length(cell.points)
    end

    has_crossed = any([cell.crossed for cell in mesh.cells])

    f = open(filename, "w")

    println(f, "# vtk DataFile Version 3.0")
    println(f, "pyfem output ")
    println(f, "ASCII")
    println(f, "DATASET UNSTRUCTURED_GRID")
    println(f, "")
    println(f, "POINTS ", npoints, " float64")

    # Write points
    for point in mesh.points
        @printf f "%23.15e %23.15e %23.15e \n" point.x point.y point.z
    end
    println(f)

    # Write connectivities
    println(f, "CELLS ",ncells, " ", ndata)
    for cell in mesh.cells
        print(f, length(cell.points), " ")
        for point in cell.points
            print(f, point.id-1, " ")
        end
        println(f)
    end
    println(f)

    # Write cell types
    println(f, "CELL_TYPES ", ncells)
    for cell in mesh.cells
        println(f, get_vtk_type(cell.shape))
    end
    println(f)

    println(f, "CELL_DATA ", ncells)

    # Write cells quality
    println(f, "SCALARS quality float 1")
    println(f, "LOOKUP_TABLE default")
    for cell in mesh.cells
        println(f, cell.quality)
    end
    println(f, )

    # Write cell type as cell data
    println(f, "SCALARS cell_type int 1")
    println(f, "LOOKUP_TABLE default")
    for cell in mesh.cells
        println(f, cell.shape)
    end
    println(f, )

    # Write flag for crossed cells
    if has_crossed
        println(f, "SCALARS crossed int 1")
        println(f, "LOOKUP_TABLE default")
        for cell in mesh.cells
            println(f, Int(cell.crossed))
        end
        println(f, )
    end

    if verbose
        println(GREEN, "  file $filename written (Mesh)", DEFAULT)
    end

    close(f)

end

function get_shape_type(geo, npoints=0)
    types = [ LIN2, LIN3, -1, TRI3, TRI6, -1, QUAD4, QUAD8, QUAD9, TET4, TET10, HEX8, HEX20, -2, LIN4, TRI10, QUAD12, QUAD16]
    shapetype = types[geo+1]
    if shapetype==-2 #joint
        shapetype = npoints==2? LINK2: LINK3
    end

    return shapetype
end

function load_mesh_vtk(filename)
    file = open(filename)
    mesh = Mesh()

    # read nodal information
    alltext = readall(f)
    data    = split(alltext)
    close(f)

    # read header
    idx  = 1
    while data[idx] != "DATASET"
        idx += 1
    end
    idx += 1

    gridtype = data[idx]
    gridtype == "UNSTRUCTURED_GRID" || error("This reader only support VTK UNSTRUCTURED_GRID.")

    # read number of points
    while data[idx] != "POINTS"
        idx += 1
    end
    npoints = parse(data[idx+1])
    idx += 3

    # read points
    for i=1:npoints
        x = parse(data[idx])
        y = parse(data[idx+1])
        z = parse(data[idx+2])
        point = Point(x,y,z)
        push!(mesh.points, point)
        idx += 3
    end

    # read number of cells
    while data[idx] != "CELLS"
        idx += 1
    end
    ncells = parse(data[idx+1])
    #ncdata = parse(data[idx+2])
    idx += 3

    # read cells connectivities
    conns = Array{Point}[]
    for i=1:ncells
        npoints = parse(data[idx])
        idx += 1
        conn = Point[]
        for j=1:npoints
            point = mesh.points( parse(data[idx]) + 1 )
            idx  += 1
            push!(conn, point)
        end
        push!(conns, conn)
    end

    # read type of cells
    types = Int[]
    while data[idx] != "CELL_TYPES"
        idx += 1
    end
    idx += 2

    # read type of cells
    for i=1:ncells
        shape = get_vtk_type( parse(data[idx]))
        cell  = Cell(shape, conns[i])
        idx  += 1
    end

    return mesh
end

function load_mesh_json(filename; format="json")
    mesh = Mesh()

    data = JSON.parsefile(filename)
    verts = data["points"]
    cells = data["cells"]

    # Loading points
    for vert in verts
        C = vert["c"]
        push!(C, 0.0)
        P = Point(C[1], C[2], C[3])
        #P.id  = vert["id"]+1
        P.id  = vert["id"]
        P.tag = string(vert["tag"])
        push!(mesh.points, P)

    end

    # Get ndim
    ndim = 2
    for point in mesh.points
        if point.z != 0.0; ndim = 3; break end
    end
    mesh.ndim = ndim

    # Loading cells
    for cell in cells
        #geo   = cell["shape"]
        conn  = cell["points"]
        #conn  = [ i+1 for i in conn]
        conn  = [ i for i in conn]
        npoints = length(conn)

        # check for embedded joint
        if haskey(cell, "jlinid") # is joint element
            lincell = cells[cell["jlinid"]]
            npoints = length(lincell["points"])
        end

        #shapetype = get_shape_type(geo, npoints)
        shapetype = eval(parse(cell["shape"]))
        points    = Point[ mesh.points[i] for i in conn ]
        C = Cell(shapetype, points, string(cell["tag"]))
        #C.id  = cell["id"]+1
        C.id  = cell["id"]
        C.ndim=ndim; 
        push!(mesh.cells, C)
    end

    # Mesh quality
    for c in mesh.cells
        update!(c)
    end

    Q = [ c.quality for c in mesh.cells]
    mesh.quality = sum(Q)/length(mesh.cells)
    mesh.qmin    = minimum(Q)

    # Generating faces
    mesh.faces = get_surface(mesh.cells)
    surf_dict = [ hash(F) => F for F in mesh.faces]

    all_faces = Face[]
    for (i,C) in enumerate(mesh.cells)
        if is_solid(C.shape)
            faces = get_faces(C)
            ftags = get(cells[i],"ftags", [])
            if length(ftags) > 0
                for (j,F) in enumerate(faces)
                    tag = string(ftags[j])
                    if ftags != "0"
                        F.tag = tag
                        surf_dict[hash(F)] = F
                    end
                end
            end
        end
    end

    mesh.faces = Cell[ face for face in values(surf_dict) ]

    return mesh
end


"""
`Mesh(filename)` constructs a mesh object based on a file in VTK legacy format or JSON format.
"""
function Mesh(filename::AbstractString)
    basename, ext = splitext(filename)
    if ext==".vtk"
        return load_mesh_vtk(filename)
    else # try JSON
        return load_mesh_json(filename)
    end
end


export rotate

"""
`rotate(mesh, [base=[0,0,0],] [axis=[0,0,1],] [angle=90.0])`

Rotates a Mesh object `mesh` according to a `base` point, an `axis` vector and an `angle`.
"""
function rotate(mesh::Mesh; base=[0.,0,0], axis=[0.,0,1], angle=90.0 )

    length(axis)==2 && ( axis=vcat(axis, 0.0) )
    length(base)==2 && ( base=vcat(base, 0.0) )

    # unit vector
    axis = axis/norm(axis)
    a, b, c = axis
    d = sqrt(b^2+c^2)
    d==0.0 && ( d=1.0 )

    # unit vector for rotation
    l = cos(angle*pi/180)
    m = sin(angle*pi/180)

    # Rotation matrices
    Rx  = [  1.    0.    0.
             0.   c/d  -b/d 
             0.   b/d   c/d ]

    Rxi = [  1.    0.    0.
             0.   c/d   b/d 
             0.  -b/d   c/d ]

    Ry  = [   d    0.  -a
             0.    1.  0.
              a    0.   d ]
           
    Ryi = [   d    0.   a
             0.    1.  0.
             -a    0.   d ]

    Rz  = [   l   -m   0.
              m    l   0.
             0.   0.   1. ]

    # all rotations matrix
    R = Rxi*Ryi*Rz*Ry*Rx

    for p in mesh.points
        p.x, p.y, p.z = base + R*([p.x, p.y, p.z] - base)
    end

    return mesh
end

# move...
"""
`move(mesh, [dx=0.0,] [dy=0.0,] [dz=0.0])` 

Moves a Mesh object `mesh`. Also returns a reference.
"""
function move(mesh::Mesh; dx=0.0, dy=0.0, dz=0.0)
    for p in mesh.points
        p.x += dx
        p.y += dy
        p.z += dz
    end
    return mesh
end

include("filters.jl") 
include("extrude.jl") 
include("smooth.jl") 
include("disjoin.jl") 
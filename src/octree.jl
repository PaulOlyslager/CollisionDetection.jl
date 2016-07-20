export Octree
export boxes, fitsinbox, boudingbox, boxesoverlap

type Box
    data::Vector{Int}
    children::Vector{Box}
end

Box() = Box(Int[], Box[])

"""
T: type of the coordinates
P: type of the points stored in the Octree
"""
type Octree{T,P}
    center::P
    halfsize::T
    rootbox::Box

    points::Vector{P}
    radii::Vector{T}

    splitcount::Int
    minhalfsize::T
end

"""
  boundingbox(v)

Compute the bounding cube/square for a Array of Point. The return values
are the center of the bounding box and the half size of the cube.
"""
function boundingbox{P}(v::Vector{P})
  #P are points values (x,y) in 2D or (x,y,z) in 3D
  ll = minimum(v)
  ur = maximum(v)
  #ll => LowerLeft
  #up => UpperRight
  c = (ll + ur)/2
  s = maximum(ur - c)
  #c => centre
  #s => biggest half width, i.e in 2D distance between points result in a rectangular
  #    (so we pick the bigger value here to form a rectangular later)
  return c, s
end


"""
Predicate used for iteration over an Octree. Returns true if two boxes
specified by their centers and halfsizes overlap. More carefull investigation
of the objects within is required to assess collision.

    boxesoverlap(c1, hs1, c2, hs2)
"""
function boxesoverlap(c1, hs1, c2, hs2)
    # Checking the type of the problem domain 2D or 3D? and making sure the boxes are from same domain
    dim = length(c1)
    @assert dim == length(c2)
    #Note: I have fixed the condition, now it works for 3D and 2D
    hs = hs1 + hs2
    for i in 1 : dim
        if abs(c1[i] - c2[i]) >= hs
            return false
        end
    end

    return true
end

function Octree{T}(points::Vector, radii::Vector{T}, splitcount = 10,  minhalfsize = zero(T))

    n_points = length(points)
    n_dims = length(eltype(points))

    # compute the bounding box taking into account
    # the radius of the objects to be inserted
    radius =  maximum(radii)
    ll = minimum(points) - radius
    ur = maximum(points) + radius

    center = (ll + ur) / 2
    halfsize = maximum(ur - center)

    # if the minimal box size is not specified,
    # make a reasonable guess
    if minhalfsize == 0
        #TODO generalise
        minhalfsize = 0.1 * halfsize * (splitcount / n_points)^(1/3)
    end

    # Create an empty octree
    rootbox = Box()
    tree = Octree(center, halfsize, rootbox, points, radii, splitcount, minhalfsize)

    # populate
    for id in 1:n_points

        point, radius = points[id], radii[id]
        insert!(tree, tree.rootbox, center, halfsize, point, radius, id)

    end

    return tree

end

"""
  Octree(points)

Insert zero radius objects at positions `points` in an Octree
"""

Octree(points) = Octree(points, zeros(eltype(eltype(points)), length(points)))



"""
    childsector(point, center) -> sector

Computes the sector w.r.t. `center` that contains  point. Sector is an Int
that encodes the position of point along each axis in its bit representation
"""
function childsector(point, center)
  # in Case of 3D the Octant they are numbered as follows (+,+,+)->7, (+,+,-)->3, (+,-,+)->5, (+,-,-)->1
  #(-,+,+)->6, (-,+,-)->2, (-,-,+)->4, (-,-,-)->0
  #For 2D (-,-)->0, (-,+)->1, (+,-)->2, (+,+)->3
	sct = 0
	r = point - center
	for (i,x) in enumerate(r)
		if x > zero(x)
			sct |= (1 << (i-1))
		end
	end

	return sct # because Julia has 1-based indexing
end

isleaf(node) = isempty(node.children)


"""
    fitsinbox(pos, radius, center, halfsize) -> true/fasle

Finds out if the object with position (pos) and (raduis) fits inside the box.
It uses the box dimension (centre, and halfsize(w/2)) to do the comparsion
"""
function fitsinbox(pos, radius, center, halfsize)

	for i in 1:length(pos)
		(pos[i] - radius < center[i] - halfsize) && return false
		(pos[i] + radius > center[i] + halfsize) && return false
	end
# the code judege by comapring with the box lower left point and uper right point
	return true
end



export childcentersize

"""
  childcentersize(center, halfsize, sector) -> center, halfsize

Computes the center and halfsize of the child of the input box
that resides in octant `sector`
"""
@generated function childcentersize(center, halfsize, sector)
  D = length(center)
  xp1 = :(halfsize = halfsize / 2)
  xp2 = Expr(:call, center)
  for d in 1:D
    push!(xp2.args, :(center[$d] + (sector & (1 << $(d-1)) == 0 ? -halfsize : +halfsize)))
  end
  xp = quote
    $xp1
    return $xp2, halfsize
  end
  #@show xp
  #xp
end



"""
insert!(tree, box, center, halfsize, point, radius, id)

tree:     the tree in which to insert
box:      the box in which to try insertion
center:   center of the box
halfsize: 0.5 times the length of the box side
point:    the point at which to insert
radius:   the radius of the item to insert
id:       a unique id that identifies the inserted item uniquely
"""
function insert!{P,T}(tree, box, center::P, halfsize::T, point::P, radius::T, id)

    # if not saturated: insert here
    # if saturated and not internal : create children and redistribute
    # if saturated and internal and not fat: insert!(childbox,...)
    # if saturated and internal and fat: insert here

    # or shorter:

    # sat & not internal: create children and redistibute
    # sat & internal & not fat: insert in childbox
    # all other cases: insert here
    # Will find out first if we are solveing octree or quadtree 3D/2D
    dim = length(P)
    nch = 2^dim

    saturated = (length(box.data) + 1) > tree.splitcount
    fat       = !fitsinbox(point, radius, center, halfsize)
    internal  = !isleaf(box)

    if !saturated || (saturated && internal && fat)

        push!(box.data, id)

    elseif saturated && internal && !fat

        sct = childsector(point, center)
        chdbox = box.children[sct+1]
        chdcenter, chdhalfsize = childcentersize(center, halfsize, sct)
        insert!(tree, chdbox, chdcenter, chdhalfsize, point, radius, id)

    else # saturated && not internal

        # if their was a previous attempt to subdivide this box,

        # insert the new element in this box for now
        push!(box.data, id)

        # if we are not allowed to subdivide any further stop. This will
        # avoid the contruction of a tree with N levels when N equal points
        # are inserted.
        if halfsize/2 < tree.minhalfsize
            return
        end

        # Create an array of childboxes
        box.children = Array(Box,nch)
        for i in 1:nch
            box.children[i] = Box(Int[], Box[])
        end


        # subdivide:
        # for every id in this box
        #   find the correspdoning child sector
        #   if it fits in the child box, insert
        #   if not, add to the list of unmovables
        # replace the current box data with the list of unmovables

        unmovables = Int[]
        for id in box.data

            point = tree.points[id]
            radius = tree.radii[id]

            sct = childsector(point, center)
            chdbox = box.children[sct+1]
            chdcenter, chdhalfsize = childcentersize(center, halfsize, sct)
            if fitsinbox(point, radius, chdcenter, chdhalfsize)
                push!(chdbox.data, id)
            else
                push!(unmovables, id)
            end

        end

        box.data = unmovables

    end

end

import Base.length
function length(tree::Octree)

    # Traversal order:
    #   data in the box
    #   data in all children
    #   data in the sibilings
    level = 0

    box = tree.rootbox
    sz = length(box.data)

    box_stack = [tree.rootbox]
    sct_stack = [1]

    sz = -0

    box = tree.rootbox
    sct = 0

    box_stack = Box[]
    sct_stack = Int[]

    while true

        # if this is the first time the box is visited, count the data
        if sct == 0
            sz += length(box.data)
            if length(box.data) != 0
                println("Adding ", length(box.data), " contributions at level: ", level)
            end
        end

        # if this box has unprocessed children
        # push this box on the stack and process the children
        if sct < length(box.children)
            push!(box_stack, box)
            push!(sct_stack, sct+1)
            level += 1

            box = box.children[sct+1]
            sct = 0

            continue
        end

        # if box and its children are processed,
        # and their is no parent above this box:
        # end the traversal:
        if isempty(box_stack)
            break
        end

        # if either no children or all children processed:
        # move up one level
        box = pop!(box_stack)
        sct = pop!(sct_stack)
        level -= 1

    end

    return sz

end


type BoxIterator{T,P,F}
    predicate::F
    tree::Octree{T,P}
end

type BoxIteratorStage{T,P}
    box::Box
    sct::Int
    center::P
    halfsize::T
end

boxes(tree::Octree, pred = (ctr,hsz)->true) = BoxIterator(pred, tree)

import Base: start, next, done
function start(bi::BoxIterator)

    pred     = bi.predicate
    center   = bi.tree.center
    halfsize = bi.tree.halfsize

    state = [ BoxIteratorStage(
        bi.tree.rootbox, 0, center, halfsize
    ) ]

    # If the rootbox does not satisfy the predicate,
    # fast forward to the next eligible box
    # take care of this deeply annoying corner case:
    if !pred(center, halfsize)
        box, state = next(bi, state)
    end

    return state

end

function next(bi::BoxIterator, state)

    item = last(state).box

    box = last(state).box   # current box
    sct = last(state).sct   # next child to visit
    hsz = last(state).halfsize
    ctr = last(state).center

    while true

        # scan for a next child box that meets the criterium
        childbox_found = false
        while sct < length(box.children)
            chd_ctr, chd_hsz = childcentersize(ctr, hsz, sct)
            if bi.predicate(chd_ctr, chd_hsz)
                childbox_found = true
                break
            end
            sct += 1
        end

        if childbox_found

            # if this box has unvisited children, increment
            # the next child sct counter and move down the tree
            last(state).sct = sct + 1
            ctr, hsz = childcentersize(ctr, hsz, sct)
            stage = BoxIteratorStage(box.children[sct+1], 0, ctr, hsz)
            push!(state, stage)

        else

            pop!(state)

        end

        # if we popped the root, we're finished
        if isempty(state)
            break
        end

        box = last(state).box
        sct = last(state).sct
        hsz = last(state).halfsize
        ctr = last(state).center

        # only stop the iteration when a new box is found
        # and if that box is non-empty
        # (sct == 0) implies that this is the first visit
        if sct == 0 && !isempty(box.data)
            break
        end

    end

    return item, state
end

done(bi::BoxIterator, state) = isempty(state)

import Base.find
function find(tr::Octree, v; tol = sqrt(eps(eltype(v))))

    pred = (c,s) -> fitsinbox(v, 0.0, c, s)
    I = Int[]
    for b in boxes(tr, pred)
      for i in b.data
        if norm(tr.points[i] - v) < tol
          push!(I, i)
        end
      end
    end

    return I

end

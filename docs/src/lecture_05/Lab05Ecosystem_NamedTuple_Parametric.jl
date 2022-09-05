using StatsBase


abstract type Species end
abstract type PlantSpecies <: Species end
abstract type Grass <: PlantSpecies end

abstract type AnimalSpecies <: Species end
abstract type Sheep <: AnimalSpecies end
abstract type Wolf <: AnimalSpecies end

abstract type Sex end
abstract type Male <: Sex end
abstract type Female <: Sex end

abstract type Agent{S<:Species} end


##########  World  #############################################################

mutable struct World{T<:NamedTuple}
    # this is a NamedTuple of Dict{Int,<:Agent}
    # but I don't know how to express that as a parametric type
    agents::T
    max_id::Int
end

function World(agents::Vector{<:Agent})
    types = unique(typeof.(agents))
    ags = map(types) do T
        as = filter(x -> isa(x,T), agents)
        Dict{Int,T}(a.id=>a for a in as)
    end
    nt = (; zip(tosym.(types), ags)...)
    
    ids = [a.id for a in agents]
    length(unique(ids)) == length(agents) || error("Not all agents have unique IDs!")
    World(nt, maximum(ids))
end

function Base.show(io::IO, w::World)
    ts = join([valtype(a) for a in w.agents], ", ")
    println(io, "World[$ts]")
    for dict in w.agents
        for (_,a) in dict
            println(io,"  $a")
        end
    end
end


##########  Animals  ###########################################################

mutable struct Animal{A<:AnimalSpecies,S<:Sex} <: Agent{A}
    id::Int
    energy::Float64
    Δenergy::Float64
    reprprob::Float64
    foodprob::Float64
end

# AnimalSpecies constructors
function (A::Type{<:AnimalSpecies})(id::Int,E::T,ΔE::T,pr::T,pf::T,S::Type{<:Sex}) where T
    Animal{A,S}(id,E,ΔE,pr,pf)
end

# get the per species defaults back
randsex() = rand(Bool) ? Female : Male
Sheep(id; E=4.0, ΔE=0.2, pr=0.6, pf=0.6, S=randsex()) = Sheep(id, E, ΔE, pr, pf, S)
Wolf(id; E=10.0, ΔE=8.0, pr=0.1, pf=0.2, S=randsex()) = Wolf(id, E, ΔE, pr, pf, S)

function Base.show(io::IO, a::Animal{A,S}) where {A<:AnimalSpecies,S<:Sex}
    e = a.energy
    d = a.Δenergy
    pr = a.reprprob
    pf = a.foodprob
    print(io, "$A$S #$(a.id) E=$e ΔE=$d pr=$pr pf=$pf")
end

# note that for new species/sexes we will only have to overload `show` on the
# abstract species/sex types like below!
Base.show(io::IO, ::Type{Sheep}) = print(io,"🐑")
Base.show(io::IO, ::Type{Wolf}) = print(io,"🐺")
Base.show(io::IO, ::Type{Male}) = print(io,"♂")
Base.show(io::IO, ::Type{Female}) = print(io,"♀")


##########  Plants  #############################################################

mutable struct Plant{P<:PlantSpecies} <: Agent{P}
    id::Int
    size::Int
    max_size::Int
end

# constructor for all Plant{<:PlantSpecies} callable as PlantSpecies(...)
(A::Type{<:PlantSpecies})(id, s, m) = Plant{A}(id,s,m)
(A::Type{<:PlantSpecies})(id, m) = (A::Type{<:PlantSpecies})(id,rand(1:m),m)

# default specific for Grass
Grass(id; max_size=10) = Grass(id, rand(1:max_size), max_size)

function Base.show(io::IO, p::Plant{P}) where P
    x = p.size/p.max_size * 100
    print(io,"$P  #$(p.id) $(round(Int,x))% grown")
end

Base.show(io::IO, ::Type{Grass}) = print(io,"🌿")


########## Eating / Dying / Reproducing  ########################################

function eat!(wolf::Animal{Wolf}, sheep::Animal{Sheep}, w::World)
    wolf.energy += sheep.energy * wolf.Δenergy
    kill_agent!(sheep,w)
end
function eat!(sheep::Animal{Sheep}, grass::Plant{Grass}, ::World)
    sheep.energy += grass.size * sheep.Δenergy
    grass.size = 0
end
eat!(::Animal, ::Nothing, ::World) = nothing

kill_agent!(a::Agent, w::World) = delete!(getfield(w.agents, tosym(typeof(a))), a.id)

function find_agent(::Type{A}, w::World) where A<:Agent
    dict = get(w.agents, tosym(A), nothing)
    if !isnothing(dict)
        as = dict |> values |> collect
        isempty(as) ? nothing : sample(as)
    else
        nothing
    end
end

find_agent(::Type{P}, w::World) where P<:PlantSpecies = find_agent(Plant{P}, w)

function find_agent(::Type{A}, w::World) where A<:AnimalSpecies
    df = get(w.agents, tosym(Animal{A,Female}), Dict{Int,Animal{A,Female}}())
    af = df |> values |> collect

    dm = get(w.agents, tosym(Animal{A,Male}), Dict{Int,Animal{A,Male}}())
    am = dm |> values |> collect

    nf = length(af)
    nm = length(am)
    if nf == 0
        # no females -> sample males
        isempty(am) ? nothing : sample(am)
    elseif nm == 0
        # no males -> sample females
        isempty(af) ? nothing : sample(af)
    else
        # both -> sample uniformly from one or the other
        rand() < nf/(nf+nm) ? sample(am) : sample(af)
    end
end

find_food(::Animal{<:Wolf}, w::World) = find_agent(Sheep, w)
find_food(::Animal{<:Sheep}, w::World) = find_agent(Grass, w)

find_mate(::Animal{A,Female}, w::World) where A<:AnimalSpecies = find_agent(Animal{A,Male}, w)
find_mate(::Animal{A,Male}, w::World) where A<:AnimalSpecies = find_agent(Animal{A,Female}, w)

function reproduce!(a::Animal{A,S}, w::World) where {A,S}
    m = find_mate(a,w)
    if !isnothing(m)
        a.energy = a.energy / 2
        vals = [getproperty(a,n) for n in fieldnames(Animal) if n!=:id]
        new_id = w.max_id + 1
        T = typeof(a)
        ŝ = T(new_id, vals...)
        getfield(w.agents, tosym(T))[ŝ.id] = ŝ
        w.max_id = new_id
    end
end
#function reproduce!(a::Animal{A,S}, w::World) where {A,S}
#    m = find_mate(a,w)
#    if !isnothing(m)
#        E = (a.energy + m.energy)/3
#        ΔE = a.Δenergy
#        pr = a.reprprob
#        pf = a.foodprob
#        new_id = w.max_id + 1
#        ŝ = Animal{A,S}(new_id, E, ΔE, pr, pf)
#        # makes things type unstable but plots look better
#        # ŝ = Animal{A,randsex()}(new_id, E, ΔE, pr, pf)
#        getfield(w.agents, tosym(ŝ))[ŝ.id] = ŝ
#
#        a.energy = a.energy * 2/3
#        m.energy = m.energy * 2/3
#        w.max_id = new_id
#        return ŝ
#    else
#        nothing
#    end
#end



##########  Stepping through time  #############################################

function agent_step!(p::Plant, ::World)
    if p.size < p.max_size
        p.size += 1
    end
end
function agent_step!(a::Animal, w::World)
    a.energy -= 1
    if rand() <= a.foodprob
        dinner = find_food(a,w)
        eat!(a, dinner, w)
    end
    if a.energy <= 0
        kill_agent!(a,w)
        return
    end
    if rand() <= a.reprprob
        reproduce!(a,w)
    end
    return a
end

function world_step!(world::World)
    # iterate over all dicts containing the different species
    map(world.agents) do species
        # make sure that we only iterate over IDs that already exist in the
        # current timestep this lets us safely add agents
        ids = copy(keys(species))
        for id in ids
            # agents can be killed by other agents, so make sure that we are
            # not stepping dead agents forward
            !haskey(species,id) && continue

            a = species[id]
            agent_step!(a, world)
        end
    end
end


##########  Counting agents  ####################################################

agent_count(p::Plant) = p.size / p.max_size
agent_count(::Animal) = 1
agent_count(as::Vector{<:Agent}) = sum(agent_count,as,init=0)
agent_count(d::Dict) = agent_count(d |> values |> collect)
agent_count(w::World) = Dict(eltype(as |> values)=>agent_count(as) for as in w.agents)


# for accessing NamedTuple in World
tosym(::Type{Animal{Wolf,Female}}) = Symbol("WolfFemale")
tosym(::Type{Animal{Wolf,Male}}) = Symbol("WolfMale")
tosym(::Type{Animal{Sheep,Female}}) = Symbol("SheepFemale")
tosym(::Type{Animal{Sheep,Male}}) = Symbol("SheepMale")
tosym(::Type{Plant{Grass}}) = Symbol("Grass")

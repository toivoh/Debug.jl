
#   Debug.Flow:
# =============
# Interactive debug trap

module Flow
using Base, Meta, AST, Graft, Eval
import AST.is_emittable, Base.isequal
export @bp, BPNode, DBState, continue!, singlestep!


type BreakPoint <: Trap; end
typealias BPNode Leaf{BreakPoint}
is_emittable(::BPNode) = false

macro bp()
    Leaf(BreakPoint())
end


type Frame
    node::Node
    scope::Scope
end
isequal(f1::Frame, f2::Frame) = (f1.node === f2.node && f1.scope === f2.scope)

abstract Cond

type Continue   <: Cond; end
type SingleStep <: Cond; end

does_trap(::SingleStep) = true
does_trap(::Continue)   = false

type DBState
    cond::Cond
    stack::Vector{Frame}

    DBState() = new(Continue(),{})
end

continue!(  s::DBState) = (s.cond = Continue())
singlestep!(s::DBState) = (s.cond = SingleStep())

enter_frame(s::DBState, ::Frame) = println("enter")
leave_frame(s::DBState, ::Frame) = println("leave")

function leave_frames(s::DBState, ::Nothing, ::Scope) 
    while !(isempty(s.stack));  leave_frame(s, pop(s.stack));  end
end
leave_frames(s::DBState, b::BlockNode, sc::Scope) = leave_frames(s,Frame(b,sc))
function leave_frames(s::DBState,frame::Frame)
    while !isempty(s.stack) && s.stack[end] != frame
        top = pop(s.stack)
        leave_frame(s, top)
    end
end
trap(s::DBState, ::BPNode, scope::Scope) = (singlestep!(s); false)
function trap(s::DBState, node::BlockNode, scope::Scope)
    if isa(scope, LocalScope)
        leave_frames(s, parent_block(node), scope.parent)
    end

    frame = Frame(node, scope)
    enter_frame(s, frame)
    push(s.stack, frame)
    false
end
function trap(s::DBState, node::Node, scope::Scope)
    leave_frames(s, parentof(node), scope)
    does_trap(s.cond)
end

parent_block(node) = blockof(parentof(node))

blockof(::Nothing)       = nothing
blockof(node::BlockNode) = node
blockof(node::Node)      = blockof(parentof(node))

end # module

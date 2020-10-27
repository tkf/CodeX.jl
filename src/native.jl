"""
    c = CodeViz.@native f(args...)
    c = CodeViz.@intel f(args...)
    c = (CodeViz.@llvm f(args...)).native
    c = (CodeViz.@llvm f(args...)).att
    c = (CodeViz.@llvm f(args...)).intel

Native code explore.

```julia
c                  # view code in the REPL
display(c)         # (ditto)
edit(c)            # open
print(c)           # print the code
abspath(c)         # file path to the text containing the code
```
"""
struct CodeNative <: AbstractCode
    code::String
    syntax::Symbol
    user_dump_module::Bool
    args::Any
    kwargs::Any
    cache::Dict{Symbol,Any}
    abspath::Base.RefValue{Union{Nothing,String}}
end

CodeNative(args::Vararg{Any,5}) =
    CodeNative(args..., Dict{Symbol,Any}(), Ref{Union{Nothing,String}}(nothing))

function Base.summary(io::IO, native::CodeNative)
    f, t = Fields(native).args
    print(io, "CodeNative of ", f, " with ", t)
    return
end

function Base.show(io::IO, ::MIME"text/plain", native::CodeNative)
    @unpack code = Fields(native)
    summary(io, native)
    println(io)
    if get(io, :color, false)
        print_native(io, code)
    else
        print(io, code)
    end
    return
end

macro native(args...)
    gen_call_with_extracted_types_and_kwargs(__module__, CodeViz.native, args)
end

macro intel(args...)
    gen_call_with_extracted_types_and_kwargs(__module__, CodeViz.intel, args)
end

function CodeViz.native(args...; dump_module = false, syntax = :att, kwargs...)
    if dump_module
        return getproperty(
            CodeViz.llvm(args...; dump_module = dump_module, kwargs...),
            syntax,
        )
    end
    @nospecialize
    code = sprint() do io
        @nospecialize
        code_native(io, args...; dump_module = true, syntax = syntax, kwargs...)
    end
    return CodeNative(code, syntax, dump_module, args, kwargs)
end

CodeViz.intel(args...; kwargs...) = CodeViz.native(args...; syntax = :intel, kwargs...)

function CodeNative(llvm::CodeLLVM, syntax::Symbol)
    @unpack user_dump_module, args, kwargs = Fields(llvm)
    CodeNative(
        llvm_to_native(llvm, `--x86-asm-syntax=$syntax`),
        syntax,
        user_dump_module,
        args,
        kwargs,
    )
end

function llvm_to_native(ir, options = ``)
    cmd = getcmd(:llc)
    cmd = `$cmd $options -o=- --filetype=asm -`
    io = IOBuffer()
    write_silently(cmd, string(ir); stdout = io)
    return String(take!(io))
end
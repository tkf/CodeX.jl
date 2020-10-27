struct CodeLLVM <: AbstractCode
    ir::String
    user_dump_module::Bool
    args::Any
    kwargs::Any
    cache::Dict{Symbol,Any}
end

Base.string(llvm::CodeLLVM) = Fields(llvm).ir
Base.print(io::IO, llvm::CodeLLVM) = print(io, string(llvm))

macro llvm(args...)
    gen_call_with_extracted_types_and_kwargs(__module__, CodeViz.llvm, args)
end

function CodeViz.llvm(args...; dump_module = false, kwargs...)
    @nospecialize
    ir = sprint() do io
        @nospecialize
        code_llvm(io, args...; dump_module = true, kwargs...)
    end
    return CodeLLVM(ir, dump_module, args, kwargs, Dict{Symbol,Any}())
end

function Base.summary(io::IO, llvm::CodeLLVM)
    f, t = Fields(llvm).args
    print(io, "CodeLLVM of ", f, " with ", t)
    return
end

function Base.show(io::IO, ::MIME"text/plain", llvm::CodeLLVM)
    @unpack ir, user_dump_module = Fields(llvm)
    summary(io, llvm)
    println(io)
    if !user_dump_module
        ir = sprint(print_main_llvm_ir, ir)
    end
    if get(io, :color, false)
        print_llvm(io, ir)
    else
        print(io, ir)
    end
    return
end

function print_main_llvm_ir(io, ir)
    input = IOBuffer(ir)
    for line in eachline(input)
        if startswith(line, "define")
            println(io, line)
            for line in eachline(input)
                println(io, line)
                if startswith(line, "}")
                    return
                end
            end
        end
    end
end

# https://llvm.org/docs/Passes.html
Base.propertynames(llvm::CodeLLVM) =
    (:callgraph, :cfg, :cfg_only, :dom, :dom_only, :postdom, :postdom_only)

# TODO: make getproperty I/O-free; just return a lazy object
Base.getproperty(llvm::CodeLLVM, name::Symbol) = get!(Fields(llvm).cache, name) do
    run_opt_dot(llvm, name)
end::LLVMDot

function run_opt_dot(llvm::CodeLLVM, name)
    ir = string(llvm)
    dotarg = "-dot-" * replace(string(name), "_" => "-")  # e.g., -dot-cfg
    dumpdir = mktempdir(prefix = "jl_codeviz_")
    cmd0 = `$(CodeViz.CONFIG.opt) $dotarg -`
    cmd = setenv(cmd0; dir = dumpdir)
    # TODO: don't hide handle error messages (if any)

    errio = IOBuffer()
    proc = open(pipeline(cmd, stderr = errio, stdout = devnull), write = true)
    try
        write(proc, ir)
    finally
        close(proc)
    end
    wait(proc)
    if proc.exitcode != 0
        error(
            "Command $cmd0 (cwd: $dumpdir) failed with code $(proc.exitcode) and error:\n",
            String(take!(errio)),
        )
    end

    return LLVMDot(llvm, cmd, dumpdir)
end

struct LLVMDot <: AbstractCode
    llvm::CodeLLVM
    cmd::Cmd
    dumpdir::String
end

Base.dirname(dot::LLVMDot) = Fields(dot).dumpdir
Base.getproperty(dot::LLVMDot, ext::Symbol) = LLVMDotImage(dot, ".$ext")

Base.abspath(dot::LLVMDot) = dotpath(dot)

dotpath(dot) = only(
    p
    for
    p in readdir(dirname(dot); join = true) if
    match(r".*\.julia_", basename(p)) !== nothing && endswith(p, ".dot")
)


struct LLVMDotImage
    dot::LLVMDot
    ext::String

    function LLVMDotImage(dot::LLVMDot, ext::String)
        @assert startswith(ext, ".")
        return new(dot, ext)
    end
end

Base.dirname(dotimg::LLVMDotImage) = dirname(Fields(dotimg).dot)

function _imagepath(dotimg::LLVMDotImage)
    @unpack dot, ext = Fields(dotimg)
    stem, _ = splitext(dotpath(dot))
    return stem * ext
end

function Base.abspath(dotimg::LLVMDotImage)
    imgpath = _imagepath(dotimg)
    ensure_dot_compile(dotpath(dotimg), imgpath)
    return imgpath
end

function dot_compile(dotpath, imgpath)
    # TODO: don't hide handle error messages (if any)
    _, ext = splitext(imgpath)
    fmt = lstrip(ext, '.')
    cmd = `$(CodeViz.CONFIG.dot) -o$imgpath -T$fmt $dotpath`
    @debug "Run: $cmd"
    run(pipeline(cmd, stdout = devnull, stderr = devnull, stdin = devnull))
end

function ensure_dot_compile(dotpath, imgpath)
    isfile(imgpath) || dot_compile(dotpath, imgpath)
    return
end

function showdot(io::IO, ext::AbstractString, dotpath::AbstractString)
    @assert startswith(ext, ".")
    stem, _ = splitext(dotpath)
    imgpath = stem * ext
    ensure_dot_compile(dotpath, imgpath)
    write(io, read(imgpath))
    return
end

Base.show(io::IO, ::MIME"image/png", dot::LLVMDot) = showdot(io, ".png", dotpath(dot))
Base.show(io::IO, ::MIME"image/svg+xml", dot::LLVMDot) = showdot(io, ".svg", dotpath(dot))
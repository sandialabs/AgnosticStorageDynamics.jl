import Pkg
Pkg.activate(@__DIR__)
Pkg.develop(Pkg.PackageSpec(path = joinpath(@__DIR__, "..")))
Pkg.instantiate()

using Documenter
using AgnosticStorageDynamics
using Literate

DocMeta.setdocmeta!(AgnosticStorageDynamics, :DocTestSetup, :(using AgnosticStorageDynamics); recursive = true)

literate_src = joinpath(@__DIR__, "literate")
generated_dst = joinpath(@__DIR__, "src", "generated")
mkpath(generated_dst)
Literate.markdown(
    joinpath(literate_src, "dynamic_profile.jl"),
    generated_dst;
    name = "dynamic_profile",
    flavor = Literate.DocumenterFlavor(),
)

makedocs(
    sitename = "AgnosticStorageDynamics.jl",
    modules = [AgnosticStorageDynamics],
    remotes = nothing,
    format = Documenter.HTML(
        prettyurls = get(ENV, "CI", "false") == "true",
        edit_link = "master",
        repolink = "https://github.com/sandialabs/AgnosticStorageDynamics.jl",
    ),
    pages = [
        "Home" => "index.md",
        "Quickstart" => "quickstart.md",
        "Usage" => "usage.md",
        "Examples" => [
            "Overview" => "examples.md",
            "Dynamic Profile" => "generated/dynamic_profile.md",
        ],
        "Theory" => "theory.md",
        "API" => "api.md",
    ],
)

if get(ENV, "CI", "false") == "true"
    deploydocs(
        repo = "github.com/sandialabs/AgnosticStorageDynamics.jl.git",
        devbranch = "master",
    )
end

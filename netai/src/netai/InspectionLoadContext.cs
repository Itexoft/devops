using System.IO;
using System.Reflection;
using System.Runtime.Loader;

namespace NetAi;

sealed class InspectionLoadContext : AssemblyLoadContext
{
    readonly string baseDirectory;

    public InspectionLoadContext(string baseDirectory) : base(isCollectible: true)
    {
        this.baseDirectory = baseDirectory;
    }

    protected override Assembly? Load(AssemblyName assemblyName)
    {
        var candidate = Path.Combine(baseDirectory, $"{assemblyName.Name}.dll");
        if (File.Exists(candidate))
        {
            return LoadFromAssemblyPath(candidate);
        }
        return null;
    }
}

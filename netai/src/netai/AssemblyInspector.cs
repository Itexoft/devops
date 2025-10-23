using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Reflection;

namespace NetAi;

sealed class AssemblyInspector
{
    public Assembly Assembly { get; }
    public string AssemblyPath { get; }
    readonly Type[] types;

    public AssemblyInspector(Assembly assembly, string assemblyPath)
    {
        Assembly = assembly;
        AssemblyPath = assemblyPath;
        types = SafeGetTypes(assembly);
    }

    Type[] SafeGetTypes(Assembly assembly)
    {
        try
        {
            return assembly.GetTypes();
        }
        catch (ReflectionTypeLoadException ex)
        {
            return ex.Types.Where(t => t != null).Cast<Type>().ToArray();
        }
    }

    public IEnumerable<Type> GetTypes(bool includePublic, bool includeNonPublic)
    {
        foreach (var type in types)
        {
            if (type == null)
            {
                continue;
            }
            var isPublic = IsTypePublic(type);
            if (!includePublic && isPublic)
            {
                continue;
            }
            if (!includeNonPublic && !isPublic)
            {
                continue;
            }
            yield return type;
        }
    }

    public Type? FindType(string? identifier)
    {
        if (string.IsNullOrWhiteSpace(identifier))
        {
            return null;
        }
        var exact = types.FirstOrDefault(t => string.Equals(t.FullName, identifier, StringComparison.Ordinal));
        if (exact != null)
        {
            return exact;
        }
        var caseInsensitive = types.FirstOrDefault(t => string.Equals(t.FullName, identifier, StringComparison.OrdinalIgnoreCase));
        if (caseInsensitive != null)
        {
            return caseInsensitive;
        }
        exact = types.FirstOrDefault(t => string.Equals(t.Name, identifier, StringComparison.Ordinal));
        if (exact != null)
        {
            return exact;
        }
        return types.FirstOrDefault(t => string.Equals(t.Name, identifier, StringComparison.OrdinalIgnoreCase));
    }

    public static bool IsTypePublic(Type type)
    {
        if (type.IsNested)
        {
            return type.IsNestedPublic || type.IsNestedFamily || type.IsNestedFamORAssem;
        }
        return type.IsPublic || type.IsVisible;
    }
}

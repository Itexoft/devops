using System;
using System.Collections.Generic;
using System.Linq;
using System.Reflection;
using System.Text.Json;

namespace NetAi;

sealed class CommandExecutor
{
    readonly AssemblyInspector inspector;

    public CommandExecutor(AssemblyInspector inspector)
    {
        this.inspector = inspector;
    }

    public int Execute(string command, OptionSet options)
    {
        return command switch
        {
            "summary" => Summary(),
            "types" => Types(options),
            "type" => TypeInfo(options),
            "members" => Members(options),
            "method" => Method(options),
            "inheritance" => Inheritance(options),
            "implements" => Implements(options),
            "search" => Search(options),
            "attributes" => Attributes(options),
            "resources" => Resources(),
            "entrypoint" => EntryPoint(),
            "dump-json" => DumpJson(options),
            _ => Unknown(command)
        };
    }

    int Summary()
    {
        var assembly = inspector.Assembly;
        var name = assembly.GetName();
        var types = inspector.GetTypes(includePublic: true, includeNonPublic: true).ToList();
        var publicCount = types.Count(AssemblyInspector.IsTypePublic);
        var nonPublicCount = types.Count - publicCount;
        Console.WriteLine($"Name: {name.Name}");
        Console.WriteLine($"Version: {name.Version}");
        Console.WriteLine($"Location: {inspector.AssemblyPath}");
        Console.WriteLine($"Modules: {string.Join(", ", assembly.Modules.Cast<Module>().Select(m => m.Name))}");
        Console.WriteLine($"Types: {types.Count} (public {publicCount}, nonpublic {nonPublicCount})");
        var namespaces = types.Where(t => t.Namespace != null).Select(t => t.Namespace!).Distinct().OrderBy(v => v, StringComparer.Ordinal).ToList();
        Console.WriteLine($"Namespaces: {namespaces.Count}");
        if (namespaces.Count > 0)
        {
            Console.WriteLine(string.Join(Environment.NewLine, namespaces));
        }
        return 0;
    }

    int Types(OptionSet options)
    {
        var includePublic = !options.Has("nonpublic") || options.Has("public");
        var includeNonPublic = !options.Has("public") || options.Has("nonpublic");
        if (!options.Has("public") && !options.Has("nonpublic"))
        {
            includePublic = true;
            includeNonPublic = true;
        }
        var types = inspector.GetTypes(includePublic, includeNonPublic);
        var namespaceFilter = options.Get("namespace");
        if (!string.IsNullOrWhiteSpace(namespaceFilter))
        {
            types = types.Where(t => (t.Namespace ?? string.Empty).StartsWith(namespaceFilter, StringComparison.OrdinalIgnoreCase));
        }
        var filter = options.Get("filter");
        if (!string.IsNullOrWhiteSpace(filter))
        {
            types = types.Where(t => t.FullName != null && t.FullName.Contains(filter, StringComparison.OrdinalIgnoreCase));
        }
        var baseFilter = options.Get("base");
        if (!string.IsNullOrWhiteSpace(baseFilter))
        {
            var baseType = inspector.FindType(baseFilter);
            if (baseType != null)
            {
                types = types.Where(t => baseType.IsAssignableFrom(t) && t != baseType);
            }
            else
            {
                types = types.Where(t => t.BaseType != null && string.Equals(t.BaseType.FullName, baseFilter, StringComparison.OrdinalIgnoreCase));
            }
        }
        var ordered = types.OrderBy(t => t.FullName, StringComparer.OrdinalIgnoreCase).ToList();
        foreach (var type in ordered)
        {
            var visibility = TypeFormatter.FormatAccessibility(type);
            var kind = TypeFormatter.FormatKind(type);
            Console.WriteLine($"{type.FullName} [{visibility}] [{kind}]");
        }
        return 0;
    }

    int TypeInfo(OptionSet options)
    {
        var identifier = options.Get("type") ?? options.Get("name") ?? options.Positional.FirstOrDefault();
        var target = inspector.FindType(identifier);
        if (target == null)
        {
            Console.Error.WriteLine("Type not found");
            return 1;
        }
        Console.WriteLine($"FullName: {target.FullName}");
        Console.WriteLine($"Namespace: {target.Namespace}");
        Console.WriteLine($"AssemblyQualifiedName: {target.AssemblyQualifiedName}");
        Console.WriteLine($"Accessibility: {TypeFormatter.FormatAccessibility(target)}");
        Console.WriteLine($"Kind: {TypeFormatter.FormatKind(target)}");
        Console.WriteLine($"Abstract: {target.IsAbstract}");
        Console.WriteLine($"Sealed: {target.IsSealed}");
        Console.WriteLine($"Static: {TypeFormatter.IsStatic(target)}");
        Console.WriteLine($"Generic: {target.IsGenericType}");
        if (target.IsGenericType)
        {
            Console.WriteLine($"GenericArguments: {string.Join(", ", target.GetGenericArguments().Select(TypeFormatter.FormatFriendly))}");
        }
        if (target.BaseType != null)
        {
            Console.WriteLine($"BaseType: {TypeFormatter.FormatFriendly(target.BaseType)}");
        }
        var interfaces = target.GetInterfaces().Select(TypeFormatter.FormatFriendly).OrderBy(v => v, StringComparer.Ordinal).ToList();
        if (interfaces.Count > 0)
        {
            Console.WriteLine("Interfaces:");
            foreach (var item in interfaces)
            {
                Console.WriteLine(item);
            }
        }
        var attributes = target.GetCustomAttributesData();
        if (attributes.Count > 0)
        {
            Console.WriteLine("Attributes:");
            foreach (var attr in attributes)
            {
                Console.WriteLine(AttributeFormatter.Format(attr));
            }
        }
        var nestedTypes = target.GetNestedTypes(BindingFlags.Public | BindingFlags.NonPublic).OrderBy(t => t.FullName, StringComparer.OrdinalIgnoreCase).ToList();
        if (nestedTypes.Count > 0)
        {
            Console.WriteLine("NestedTypes:");
            foreach (var nested in nestedTypes)
            {
                Console.WriteLine($"{nested.FullName} [{TypeFormatter.FormatAccessibility(nested)}] [{TypeFormatter.FormatKind(nested)}]");
            }
        }
        return 0;
    }

    int Members(OptionSet options)
    {
        var target = ResolveTypeWithRemainder(options, out var remainder);
        if (target == null)
        {
            Console.Error.WriteLine("Type not found");
            return 1;
        }
        var includeNonPublic = options.Has("include-nonpublic") || options.Has("nonpublic");
        var kinds = new HashSet<string>(options.GetAll("kind"), StringComparer.OrdinalIgnoreCase);
        foreach (var item in remainder)
        {
            kinds.Add(item);
        }
        if (kinds.Count == 0)
        {
            kinds.UnionWith(new[] { "methods", "constructors", "properties", "fields", "events" });
        }
        var bindingFlags = BindingFlags.Public | BindingFlags.Instance | BindingFlags.Static;
        if (includeNonPublic)
        {
            bindingFlags |= BindingFlags.NonPublic;
        }
        if (kinds.Contains("methods"))
        {
            foreach (var method in target.GetMethods(bindingFlags).OrderBy(m => m.Name, StringComparer.Ordinal))
            {
                Console.WriteLine(MethodFormatter.Format(method));
            }
        }
        if (kinds.Contains("constructors"))
        {
            foreach (var ctor in target.GetConstructors(bindingFlags).OrderBy(m => m.ToString(), StringComparer.Ordinal))
            {
                Console.WriteLine(MethodFormatter.Format(ctor));
            }
        }
        if (kinds.Contains("properties"))
        {
            foreach (var property in target.GetProperties(bindingFlags).OrderBy(p => p.Name, StringComparer.Ordinal))
            {
                Console.WriteLine(PropertyFormatter.Format(property, includeNonPublic));
            }
        }
        if (kinds.Contains("fields"))
        {
            foreach (var field in target.GetFields(bindingFlags).OrderBy(f => f.Name, StringComparer.Ordinal))
            {
                Console.WriteLine(FieldFormatter.Format(field));
            }
        }
        if (kinds.Contains("events"))
        {
            foreach (var evt in target.GetEvents(bindingFlags).OrderBy(e => e.Name, StringComparer.Ordinal))
            {
                Console.WriteLine(EventFormatter.Format(evt));
            }
        }
        return 0;
    }

    int Method(OptionSet options)
    {
        var target = ResolveTypeWithRemainder(options, out var remainder);
        if (target == null)
        {
            Console.Error.WriteLine("Type not found");
            return 1;
        }
        string? name = options.Get("method") ?? options.Get("member") ?? options.Get("name");
        if (string.IsNullOrWhiteSpace(name) && remainder.Count > 0)
        {
            name = remainder[0];
            remainder.RemoveAt(0);
        }
        if (string.IsNullOrWhiteSpace(name))
        {
            Console.Error.WriteLine("Method name required");
            return 1;
        }
        var includeNonPublic = options.Has("include-nonpublic") || options.Has("nonpublic");
        var bindingFlags = BindingFlags.Public | BindingFlags.Instance | BindingFlags.Static;
        if (includeNonPublic)
        {
            bindingFlags |= BindingFlags.NonPublic;
        }
        var parametersFilter = options.Get("parameters");
        var candidates = target.GetMethods(bindingFlags).Where(m => string.Equals(m.Name, name, StringComparison.OrdinalIgnoreCase)).ToList();
        if (!string.IsNullOrWhiteSpace(parametersFilter))
        {
            var parameterTypes = parametersFilter.Split(',', StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries);
            candidates = candidates.Where(m => MatchesParameters(m, parameterTypes)).ToList();
        }
        if (candidates.Count == 0)
        {
            Console.Error.WriteLine("Method not found");
            return 1;
        }
        foreach (var method in candidates)
        {
            Console.WriteLine(MethodFormatter.FormatDetailed(method));
        }
        return 0;
    }

    bool MatchesParameters(MethodBase method, IReadOnlyList<string> typeNames)
    {
        var parameters = method.GetParameters();
        if (parameters.Length != typeNames.Count)
        {
            return false;
        }
        for (var i = 0; i < parameters.Length; i++)
        {
            var parameter = parameters[i];
            var typeName = TypeFormatter.FormatFriendly(parameter.ParameterType);
            if (!string.Equals(typeName, typeNames[i], StringComparison.OrdinalIgnoreCase) &&
                !string.Equals(parameter.ParameterType.Name, typeNames[i], StringComparison.OrdinalIgnoreCase))
            {
                return false;
            }
        }
        return true;
    }

    int Inheritance(OptionSet options)
    {
        var identifier = options.Get("type") ?? options.Positional.FirstOrDefault();
        var target = inspector.FindType(identifier);
        if (target == null)
        {
            Console.Error.WriteLine("Type not found");
            return 1;
        }
        var chain = new List<Type>();
        var current = target;
        while (current != null)
        {
            chain.Add(current);
            current = current.BaseType;
        }
        foreach (var type in chain)
        {
            Console.WriteLine(TypeFormatter.FormatFriendly(type));
        }
        return 0;
    }

    int Implements(OptionSet options)
    {
        var identifier = options.Get("type") ?? options.Get("interface") ?? options.Positional.FirstOrDefault();
        if (string.IsNullOrWhiteSpace(identifier))
        {
            Console.Error.WriteLine("Type or interface required");
            return 1;
        }
        var target = inspector.FindType(identifier);
        if (target == null)
        {
            Console.Error.WriteLine("Reference type not found");
            return 1;
        }
        var includeNonPublic = options.Has("include-nonpublic") || options.Has("nonpublic");
        var types = inspector.GetTypes(includePublic: true, includeNonPublic).Where(t => t != target && target.IsAssignableFrom(t)).OrderBy(t => t.FullName, StringComparer.OrdinalIgnoreCase).ToList();
        foreach (var type in types)
        {
            Console.WriteLine($"{type.FullName} [{TypeFormatter.FormatKind(type)}]");
        }
        return 0;
    }

    int Search(OptionSet options)
    {
        var pattern = options.Get("pattern") ?? options.Positional.FirstOrDefault();
        if (string.IsNullOrWhiteSpace(pattern))
        {
            Console.Error.WriteLine("Pattern required");
            return 1;
        }
        var comparison = options.Has("case-sensitive") ? StringComparison.Ordinal : StringComparison.OrdinalIgnoreCase;
        var includeNonPublic = options.Has("include-nonpublic") || options.Has("nonpublic");
        var bindingFlags = BindingFlags.Public | BindingFlags.Instance | BindingFlags.Static;
        if (includeNonPublic)
        {
            bindingFlags |= BindingFlags.NonPublic;
        }
        foreach (var type in inspector.GetTypes(includePublic: true, includeNonPublic: includeNonPublic))
        {
            var fullName = type.FullName ?? type.Name;
            if (fullName != null && fullName.Contains(pattern, comparison))
            {
                Console.WriteLine($"{fullName} [type]");
            }
            foreach (var method in type.GetMethods(bindingFlags))
            {
                if (method.Name.Contains(pattern, comparison))
                {
                    Console.WriteLine($"{type.FullName} :: {MethodFormatter.Format(method)}");
                }
            }
            foreach (var property in type.GetProperties(bindingFlags))
            {
                if (property.Name.Contains(pattern, comparison))
                {
                    Console.WriteLine($"{type.FullName} :: {PropertyFormatter.Format(property, includeNonPublic)}");
                }
            }
            foreach (var field in type.GetFields(bindingFlags))
            {
                if (field.Name.Contains(pattern, comparison))
                {
                    Console.WriteLine($"{type.FullName} :: {FieldFormatter.Format(field)}");
                }
            }
        }
        return 0;
    }

    int Attributes(OptionSet options)
    {
        if (options.Has("member"))
        {
            return MemberAttributes(options);
        }
        var identifier = options.Get("type") ?? options.Positional.FirstOrDefault();
        var target = inspector.FindType(identifier);
        if (target == null)
        {
            Console.Error.WriteLine("Type not found");
            return 1;
        }
        var attributes = target.GetCustomAttributesData();
        foreach (var attr in attributes)
        {
            Console.WriteLine(AttributeFormatter.Format(attr));
        }
        return 0;
    }

    int MemberAttributes(OptionSet options)
    {
        var target = ResolveTypeWithRemainder(options, out var remainder);
        var memberSpec = options.Get("member");
        if (string.IsNullOrWhiteSpace(memberSpec) && remainder.Count > 0)
        {
            memberSpec = remainder[0];
        }
        if (target == null || string.IsNullOrWhiteSpace(memberSpec))
        {
            Console.Error.WriteLine("Type and member required");
            return 1;
        }
        var includeNonPublic = options.Has("include-nonpublic") || options.Has("nonpublic");
        var bindingFlags = BindingFlags.Public | BindingFlags.Instance | BindingFlags.Static;
        if (includeNonPublic)
        {
            bindingFlags |= BindingFlags.NonPublic;
        }
        MemberInfo? member = target.GetMethods(bindingFlags).FirstOrDefault(m => string.Equals(m.Name, memberSpec, StringComparison.OrdinalIgnoreCase));
        member ??= target.GetProperties(bindingFlags).FirstOrDefault(m => string.Equals(m.Name, memberSpec, StringComparison.OrdinalIgnoreCase));
        member ??= target.GetFields(bindingFlags).FirstOrDefault(m => string.Equals(m.Name, memberSpec, StringComparison.OrdinalIgnoreCase));
        member ??= target.GetEvents(bindingFlags).FirstOrDefault(m => string.Equals(m.Name, memberSpec, StringComparison.OrdinalIgnoreCase));
        if (member == null)
        {
            Console.Error.WriteLine("Member not found");
            return 1;
        }
        var attributes = CustomAttributeData.GetCustomAttributes(member);
        foreach (var attr in attributes)
        {
            Console.WriteLine(AttributeFormatter.Format(attr));
        }
        return 0;
    }

    int Resources()
    {
        var names = inspector.Assembly.GetManifestResourceNames();
        foreach (var name in names)
        {
            using var stream = inspector.Assembly.GetManifestResourceStream(name);
            var length = stream?.Length ?? 0;
            Console.WriteLine($"{name} ({length} bytes)");
        }
        return 0;
    }

    int EntryPoint()
    {
        var entry = inspector.Assembly.EntryPoint;
        if (entry == null)
        {
            Console.WriteLine("EntryPoint: none");
            return 0;
        }
        Console.WriteLine($"EntryPoint: {entry.DeclaringType?.FullName}.{entry.Name}");
        Console.WriteLine(MethodFormatter.Format(entry));
        return 0;
    }

    int DumpJson(OptionSet options)
    {
        var result = new AssemblyModel
        {
            Name = inspector.Assembly.GetName().Name ?? string.Empty,
            Version = inspector.Assembly.GetName().Version?.ToString(),
            Location = inspector.AssemblyPath,
            Types = new List<TypeModel>()
        };
        var includeNonPublic = options.Has("include-nonpublic") || options.Has("nonpublic");
        var identifier = options.Get("type") ?? options.Get("name") ?? options.Positional.FirstOrDefault();
        if (!string.IsNullOrWhiteSpace(identifier))
        {
            var type = inspector.FindType(identifier);
            if (type != null)
            {
                result.Types.Add(JsonBuilder.BuildTypeModel(type, includeMembers: true, includeNonPublic: includeNonPublic));
            }
        }
        else
        {
            foreach (var type in inspector.GetTypes(includePublic: true, includeNonPublic: includeNonPublic))
            {
                result.Types.Add(JsonBuilder.BuildTypeModel(type, includeMembers: options.Has("with-members"), includeNonPublic: includeNonPublic));
            }
        }
        var output = JsonSerializer.Serialize(result, new JsonSerializerOptions { WriteIndented = true });
        Console.WriteLine(output);
        return 0;
    }

    int Unknown(string command)
    {
        Console.Error.WriteLine($"Unknown command: {command}");
        return 1;
    }

    Type? ResolveTypeWithRemainder(OptionSet options, out List<string> remainder)
    {
        remainder = new List<string>(options.Positional);
        var identifier = options.Get("type");
        if (string.IsNullOrWhiteSpace(identifier))
        {
            if (remainder.Count > 0)
            {
                identifier = remainder[0];
                remainder.RemoveAt(0);
            }
        }
        return inspector.FindType(identifier);
    }
}

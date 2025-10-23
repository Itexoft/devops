using System;
using System.Linq;
using System.Reflection;
using System.Text;

namespace NetAi;

static class TypeFormatter
{
    public static string FormatFriendly(Type type)
    {
        if (type.IsGenericType && !type.IsGenericTypeDefinition)
        {
            var builder = new StringBuilder();
            builder.Append(type.GetGenericTypeDefinition().FullName?.Split('`')[0]);
            builder.Append("<");
            builder.Append(string.Join(", ", type.GetGenericArguments().Select(FormatFriendly)));
            builder.Append(">");
            return builder.ToString();
        }
        if (type.IsArray)
        {
            return $"{FormatFriendly(type.GetElementType()!)}[{new string(',', type.GetArrayRank() - 1)}]";
        }
        return type.FullName ?? type.Name;
    }

    public static string FormatAccessibility(Type type)
    {
        if (type.IsNested)
        {
            if (type.IsNestedPublic) return "public";
            if (type.IsNestedFamily) return "protected";
            if (type.IsNestedFamORAssem) return "protected internal";
            if (type.IsNestedPrivate) return "private";
            if (type.IsNestedAssembly) return "internal";
            if (type.IsNestedFamANDAssem) return "private protected";
            return "unknown";
        }
        if (type.IsPublic || type.IsVisible) return "public";
        if (type.IsNotPublic) return "internal";
        return "unknown";
    }

    public static string FormatKind(Type type)
    {
        if (type.IsInterface) return "interface";
        if (type.IsEnum) return "enum";
        if (type.IsValueType && !type.IsPrimitive) return "struct";
        if (type.IsClass && type.IsSealed && type.IsAbstract) return "static class";
        if (type.IsClass) return "class";
        return "type";
    }

    public static bool IsStatic(Type type) => type.IsAbstract && type.IsSealed;
}

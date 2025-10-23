using System.Reflection;

namespace NetAi;

static class FieldFormatter
{
    public static string Format(FieldInfo field)
    {
        return $"{TypeFormatter.FormatFriendly(field.DeclaringType!)}.{field.Name} : {TypeFormatter.FormatFriendly(field.FieldType)} [{FormatAccessibility(field)}{(field.IsStatic ? ", static" : string.Empty)}]";
    }

    static string FormatAccessibility(FieldInfo field)
    {
        if (field.IsPublic) return "public";
        if (field.IsFamily) return "protected";
        if (field.IsFamilyOrAssembly) return "protected internal";
        if (field.IsAssembly) return "internal";
        if (field.IsPrivate) return "private";
        if (field.IsFamilyAndAssembly) return "private protected";
        return "unknown";
    }
}

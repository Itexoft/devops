using System.Linq;
using System.Reflection;
using System.Text;

namespace NetAi;

static class MethodFormatter
{
    public static string Format(MethodBase method)
    {
        var builder = new StringBuilder();
        builder.Append($"{TypeFormatter.FormatFriendly(method.DeclaringType!)}.{method.Name}");
        if (method.IsGenericMethod)
        {
            builder.Append("<");
            builder.Append(string.Join(", ", method.GetGenericArguments().Select(TypeFormatter.FormatFriendly)));
            builder.Append(">");
        }
        builder.Append("(");
        builder.Append(string.Join(", ", method.GetParameters().Select(ParameterFormatter.Format)));
        builder.Append(")");
        return builder.ToString();
    }

    public static string FormatDetailed(MethodBase method)
    {
        var builder = new StringBuilder();
        builder.AppendLine(Format(method));
        builder.AppendLine($"Accessibility: {FormatAccessibility(method)}");
        builder.AppendLine($"Static: {method.IsStatic}");
        builder.AppendLine($"Virtual: {method.IsVirtual}");
        builder.AppendLine($"Abstract: {method.IsAbstract}");
        if (method is MethodInfo info)
        {
            builder.AppendLine($"ReturnType: {TypeFormatter.FormatFriendly(info.ReturnType)}");
        }
        var attributes = CustomAttributeData.GetCustomAttributes(method);
        if (attributes.Count > 0)
        {
            builder.AppendLine("Attributes:");
            foreach (var attr in attributes)
            {
                builder.AppendLine(AttributeFormatter.Format(attr));
            }
        }
        var methodBody = method.GetMethodBody();
        if (methodBody != null)
        {
            builder.AppendLine($"ILSize: {methodBody.GetILAsByteArray()?.Length ?? 0}");
            builder.AppendLine($"LocalVariables: {methodBody.LocalVariables.Count}");
        }
        return builder.ToString().TrimEnd();
    }

    static string FormatAccessibility(MethodBase method)
    {
        if (method.IsPublic) return "public";
        if (method.IsFamily) return "protected";
        if (method.IsFamilyOrAssembly) return "protected internal";
        if (method.IsAssembly) return "internal";
        if (method.IsFamilyAndAssembly) return "private protected";
        if (method.IsPrivate) return "private";
        return "unknown";
    }
}

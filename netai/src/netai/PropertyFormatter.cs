using System.Linq;
using System.Reflection;

namespace NetAi;

static class PropertyFormatter
{
    public static string Format(PropertyInfo property, bool includeNonPublic)
    {
        var accessors = property.GetAccessors(includeNonPublic);
        return $"{TypeFormatter.FormatFriendly(property.DeclaringType!)}.{property.Name} : {TypeFormatter.FormatFriendly(property.PropertyType)} [{string.Join(", ", accessors.Select(a => a.Name))}]";
    }
}

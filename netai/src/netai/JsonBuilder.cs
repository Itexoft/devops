using System;
using System.Collections.Generic;
using System.Linq;
using System.Reflection;

namespace NetAi;

static class JsonBuilder
{
    public static TypeModel BuildTypeModel(Type type, bool includeMembers, bool includeNonPublic)
    {
        var model = new TypeModel
        {
            FullName = type.FullName ?? type.Name,
            Accessibility = TypeFormatter.FormatAccessibility(type),
            Kind = TypeFormatter.FormatKind(type),
            BaseType = type.BaseType != null ? TypeFormatter.FormatFriendly(type.BaseType) : null,
            Interfaces = type.GetInterfaces().Select(TypeFormatter.FormatFriendly).OrderBy(v => v, System.StringComparer.Ordinal).ToList(),
            Attributes = type.GetCustomAttributesData().Select(AttributeFormatter.Format).ToList(),
            Members = new List<MemberModel>()
        };
        if (includeMembers)
        {
            var bindingFlags = BindingFlags.Public | BindingFlags.Instance | BindingFlags.Static;
            if (includeNonPublic)
            {
                bindingFlags |= BindingFlags.NonPublic;
            }
            foreach (var method in type.GetMethods(bindingFlags))
            {
                model.Members.Add(new MemberModel { Kind = "method", Name = method.Name, Signature = MethodFormatter.Format(method) });
            }
            foreach (var property in type.GetProperties(bindingFlags))
            {
                model.Members.Add(new MemberModel { Kind = "property", Name = property.Name, Signature = PropertyFormatter.Format(property, includeNonPublic) });
            }
            foreach (var field in type.GetFields(bindingFlags))
            {
                model.Members.Add(new MemberModel { Kind = "field", Name = field.Name, Signature = FieldFormatter.Format(field) });
            }
            foreach (var evt in type.GetEvents(bindingFlags))
            {
                model.Members.Add(new MemberModel { Kind = "event", Name = evt.Name, Signature = EventFormatter.Format(evt) });
            }
        }
        return model;
    }
}

sealed class AssemblyModel
{
    public string Name { get; set; } = string.Empty;
    public string? Version { get; set; }
    public string Location { get; set; } = string.Empty;
    public List<TypeModel> Types { get; set; } = new();
}

sealed class TypeModel
{
    public string FullName { get; set; } = string.Empty;
    public string Accessibility { get; set; } = string.Empty;
    public string Kind { get; set; } = string.Empty;
    public string? BaseType { get; set; }
    public List<string> Interfaces { get; set; } = new();
    public List<string> Attributes { get; set; } = new();
    public List<MemberModel> Members { get; set; } = new();
}

sealed class MemberModel
{
    public string Kind { get; set; } = string.Empty;
    public string Name { get; set; } = string.Empty;
    public string Signature { get; set; } = string.Empty;
}

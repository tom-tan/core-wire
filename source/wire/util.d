/**
 * Authors: Tomoya Tanjo
 * Copyright: © 2022 Tomoya Tanjo
 * License: Apache-2.0
 */
module wire.util;

import dyaml : Node;
import std : exists, getcwd, isFile, JSONValue;

/** 
 * Returns: an absolute URI
 *
 * Note: It assumes that a string with "://" is an absolute URI
 */
auto isAbsoluteURI(string uriOrPath) @nogc nothrow pure @safe
{
    import std.algorithm : canFind;
    return uriOrPath.canFind("://");
}

/**
 * Returns: an absolute URI with scheme
 * Params: 
 *   pathOrURI = a string that is an absolute or relative local path, or a URI
 *   base  = a base directory
 */
auto absoluteURI(string pathOrURI, string base = getcwd()) nothrow pure @safe
{
    import std.path : isAbsolute;

    if (pathOrURI.isAbsoluteURI)
    {
        return pathOrURI;
    }
    else if (pathOrURI.isAbsolute)
    {
        return "file://"~pathOrURI;
    }
    else if (base.isAbsolute)
    {
        import std.exception : assumeUnique, assumeWontThrow;
        import std.path : absolutePath, asNormalizedPath;
        import std.array : array;
        auto absPath = pathOrURI.absolutePath(base)
                                .assumeWontThrow
                                .asNormalizedPath
                                .array;
        return "file://"~(() @trusted => absPath.assumeUnique)();
    }
    else
    {
        assert(base.isAbsoluteURI);
        auto sc = base.scheme; // assumes `base` starts with `$sc://`
        auto abs = pathOrURI.absoluteURI(base[sc.length+2..$]);
        return sc~"://"~abs[(sc == "file" ? 7 : 8)..$];
    }
}

pure @safe unittest
{
    assert("http://example.com/foo/bar".absoluteURI == "http://example.com/foo/bar");
    assert("/foo/bar/buzz".absoluteURI == "file:///foo/bar/buzz");
    assert("../fuga/piyo".absoluteURI("http://example.com/foo/bar")
        == "http://example.com/foo/fuga/piyo");
    assert("../fuga/piyo".absoluteURI("/foo/bar")
        == "file:///foo/fuga/piyo");
}

///
string scheme(string uri) @nogc nothrow pure @safe
{
    import std.algorithm : findSplit;
    if (auto ret = uri.findSplit("://"))
    {
        return ret[0];
    }
    return "";
}

///
string path(string uri) pure @safe
{
    import std.algorithm : findSplit;
    if (auto ret = uri.findSplit("://"))
    {
        return ret[2];
    }
    return uri;
}

///
auto calcChecksum(string path) @trusted
in(path.exists)
in(path.isFile)
{
    import std.digest.sha : SHA1;
    import std : chunks, File, toHexString;

    SHA1 hash;
    hash.start;

    auto file = File(path);
    foreach(ubyte[] buf; chunks(file, 4096))
    {
        hash.put(buf);
    }
    return toHexString(hash.finish);
}

///
JSONValue toJSON(Node node) @safe
{
    import dyaml : NodeType;
    import std.algorithm : fold, map;
    import std.array : array;
    import std.format : format;

    switch(node.type)
    {
    case NodeType.null_: return JSONValue(null);
    case NodeType.boolean: return JSONValue(node.as!bool);
    case NodeType.integer: return JSONValue(node.as!long);
    case NodeType.decimal: return JSONValue(node.as!real);
    case NodeType.string: return JSONValue(node.as!string);
    case NodeType.mapping:
        return node.mapping.fold!((acc, e) {
            acc[e.key.as!string] = e.value.toJSON;
            return acc;
        })(JSONValue((JSONValue[string]).init));
    case NodeType.sequence:
        return JSONValue(node.sequence.map!(e => e.toJSON).array);
    default: assert(false, format!"Invalid node type: %s"(node.type));
    }
}

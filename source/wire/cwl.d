/**
 * Authors: Tomoya Tanjo
 * Copyright: © 2022 Tomoya Tanjo
 * License: Apache-2.0
 */
module wire.cwl;

import dyaml;

import wire : Wire;

/**
 * It makes a new sub directory for each parameter
 */
Node download(Node input, string destURI, Wire wire)
in(destURI.scheme == "file")
{
    import std.file : mkdir, rmdirRecurse, tempDir;
    import std.path : buildPath;
    import std.uuid : randomUUID;

    auto dir = buildPath(tempDir, randomUUID.toString);
    mkdir(dir);

    scope(failure)
    {
        // leave in error?
        rmdirRecurse(dir);
    }

    // make tmpdir
    // download[scheme] to tmpdir
    // URI already exists -> copy & remove
    // otherwise -> move
}

///
Node upload(Node input, string destURI, Wire wire)
{
    // make tmpdir
    // download[file,copy/symlink] to tmpdir
    // copy & remove
}

///
Node staging(Node input, string dst, Wire wire)
{
    import std.exception : enforce;

    enforce(input.type == NodeType.mapping);

    auto ret = Node((Node[string]).init);
    foreach(string k, Node v; input)
    {
        import std : canFind;
        Node val = k.canFind(":")
            ? v
            : v.stagingParam(dst, wire);

        if (val.type != NodeType.null_)
        {
            ret.add(k, val);
        }
    }
    return ret;
}

///
Node stagingParam(Node inp, string dst, Wire wire)
{
    import std : format;
    import wire.exception : WireException;

    switch(inp.type)
    {
    case NodeType.null_:
        return Node(YAMLNull());
    case NodeType.boolean, NodeType.integer, NodeType.decimal, NodeType.string:
        return inp;
    case NodeType.sequence:
        import std : array, map;
        return Node(
            inp.sequence.map!(i => i.stagingParam(dst, wire)).array
        );
    case NodeType.mapping:
        if (auto class_ = "class" in inp)
        {
            auto c = class_.as!string;
            switch(c)
            {
            case "File": return inp.stagingFile(dst, wire);
            case "Directory": return inp.stagingDirectory(dst, wire);
            default:
                throw new WireException(format!"Unknown class: `%s`"(c));
            }
        }
        return inp.staging(dst, wire);
    default:
        throw new WireException(format!"Unsupported node type: `%s`"(inp.type));
    }
}

/// TODO
auto stagingFile(Node file, string dst, Wire wire)
{
    import std : absolutePath, buildPath, dirName;

    Node ret = Node(file);
    ret.add("location", buildPath(file.startMark.name.dirName, file["location"].as!string));
    if (auto sec = "secondaryFiles" in file)
    {
        import std : array, map;
        auto sf = sec.sequence.map!(s => s.stagingParam(dst, wire)).array;
        ret.add("secondaryFiles", sf);
    }
    return ret;
}

/// TODO
auto stagingDirectory(Node dir, string dst, Wire wire)
{
    Node ret;
    ret.add("class", "Directory");
    return dir;
}

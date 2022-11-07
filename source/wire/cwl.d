/**
 * Authors: Tomoya Tanjo
 * Copyright: © 2022 Tomoya Tanjo
 * License: Apache-2.0
 */
module wire.cwl;

import dyaml;

import std : exists;

import wire : Wire;
import wire.core : CoreWireConfig;
import wire.util;

///
enum LeaveTmpdir
{
    always,
    onErrors,
    never,
}

struct DownloadConfig
{
    ///
    LeaveTmpdir leaveTmpDir;
    /// make random directory for each parameter or not
    bool makeRandomDir;

    /// 
    CoreWireConfig[string] config; // option to overwrite given options (is it needed?)
}

/**
 * It makes a new sub directory for each parameter 
 */
Node download(Node input, string destURI, Wire wire, DownloadConfig con)
in(destURI.scheme == "file")
in(input.type == NodeType.mapping)
{
    import std.file : dirEntries, exists, rename, mkdir, rmdirRecurse, SpanMode, tempDir;
    import std.path : baseName, buildPath;
    import std.uuid : randomUUID;

    auto dir = buildPath(tempDir, randomUUID.toString);
    mkdir(dir);
    scope(success)
    {
        if (dir.exists && con.leaveTmpDir == LeaveTmpdir.never)
        {
            rmdirRecurse(dir);
        }
    }
    scope(failure)
    {
        if (dir.exists && con.leaveTmpDir != LeaveTmpdir.always)
        {
            rmdirRecurse(dir);
        }
    }

    auto destPath = destURI.path;

    Node ret;
    foreach(string k, Node v; input)
    {
        import std : canFind;
        Node val;
        if (k.canFind(":"))
        {
            val = v;
        }
        else
        {
            auto dest = con.makeRandomDir
                ? buildPath(destPath, randomUUID.toString)
                : destPath;
            val = downloadParam(v, "file://"~dest, wire, con);
        }

        if (val.type != NodeType.null_)
        {
            ret.add(k, val);
        }
    }

    if (destPath.exists)
    {
        foreach(string name; dirEntries(dir, SpanMode.shallow))
        {
            rename(name, buildPath(destPath, name.baseName));
        }
        rmdirRecurse(dir);
    }
    else
    {
        rename(dir, destPath);
    }
    return ret;
}

///
Node upload(Node input, string destURI, Wire wire)
{
    // make tmpdir
    // download[file,copy/symlink] to tmpdir
    // copy & remove
    return input;
}

///
Node downloadParam(Node inp, string dest, Wire wire, DownloadConfig con)
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
            inp.sequence.map!(i => i.downloadParam(dest, wire, con)).array
        );
    case NodeType.mapping:
        if (auto class_ = "class" in inp)
        {
            auto c = class_.as!string;
            switch(c)
            {
            case "File": return inp.downloadFile(dest, wire, con);
            case "Directory": return inp.downloadDirectory(dest, wire, con);
            default:
                throw new WireException(format!"Unknown class: `%s`"(c));
            }
        }
        return download(inp, dest, wire, con);
    default:
        throw new WireException(format!"Unsupported node type: `%s`"(inp.type));
    }
}

///
auto downloadFile(Node file, string dest, Wire wire, DownloadConfig config)
in(file.type == NodeType.mapping)
in("class" in file)
in(file["class"] == "File")
in(dest.scheme == "file")
in(dest.path.exists)
{
    import std : absolutePath, buildPath, dirName;

    auto cFile = file.toCanonicalFile;
    string loc;

    if (auto con = "contents" in cFile)
    {
        import std.file : write;

        // file literal
        string bname;
        if (auto bn_ = "basename" in cFile)
        {
            bname = bn_.as!string;
        }
        else
        {
            import std : randomUUID;
            bname = randomUUID.toString;
        }
        auto destPath = buildPath(dest.path, bname);
        destPath.write(con.as!string);
        loc = "file://"~destPath;
    }
    else
    {
        auto destURI = buildPath(dest, cFile["basename"].as!string);
        wire.downloadFile(cFile["location"].as!string, destURI);
        loc = destURI;
    }

    Node ret = Node(cFile);
    ret["location"] = loc;
    ret["path"] = loc.path;
    if (auto sec = "secondaryFiles" in cFile)
    {
        import std : array, map;
        auto sf = sec.sequence.map!(s => downloadParam(s, dest, wire, config)).array;
        ret["secondaryFiles"] = sf;
    }
    return ret;
}

unittest
{
    // file to file
    // File w/o secondaryFiles
}

unittest
{
    // file to file
    // File w/ secondaryFiles
}

/**
 * Returns: A canonicalized File object. That is,
 *   - File object in which `contents` and `basename` are available but `path` and `location` are not available
 *   - File object in which `location` and `basename` is available but `path` and `contents` are not available
 * Throws: Exception when `file` is not a valid File object.
 */
Node toCanonicalFile(Node file)
in(file.type == NodeType.mapping)
in("class" in file)
in(file["class"] == "File")
{
    import std : enforce;

    auto ret = Node(file);
    auto path_ = "path" in file;
    auto loc_ = "location" in file;
    auto pwd = file.startMark.name;
    if (path_ is null && loc_ is null)
    {
        // file literal
        auto con = enforce("contents" in file);
        enforce(con.type == NodeType.string);
        enforce(con.as!string.length <= 64*2^^10);
    }
    else if (loc_ !is null)
    {
        ret["location"] = loc_.as!string.absoluteURI(pwd);
        ret.remove("path");
        ret.remove("contents");
    }
    else if (path_ !is null)
    {
        ret["location"] = path_.as!string.absoluteURI(pwd);
        ret.remove("path");
        ret.remove("contents");
    }

    if (auto bname = "basename" in file)
    {
        import std : canFind;

        enforce(!bname.as!string.canFind("/"));
    }
    else if (auto p_ = "location" in ret)
    {
        import std : baseName;
        ret["basename"] = p_.as!string.path.baseName;
    }

    // TODO: how to do with `size` and `checksum`?

    if (auto sec = "secondaryFiles" in file)
    {
        import std : array, map;

        auto canonicalizedSec = sec
            .sequence
            .map!((s)
            {
                auto class_ = enforce("class" in s).as!string;
                if (class_ == "File")
                {
                    return s.toCanonicalFile;
                }
                else if (class_ == "Directory")
                {
                    return s.toCanonicalDirectory;
                }
                throw new Exception("Unknown class: "~class_);
            })
            .array;
        ret["secondaryFiles"] = canonicalizedSec;
    }

    return ret;
}

/// File object that indicates an actual file
unittest
{
    import dyaml : Loader;

    enum lit = q"EOS
    class: File
    location: /foo/bar/buzz.txt
EOS";

    auto cFile = Loader.fromString(lit).load.toCanonicalFile;

    assert("class" in cFile);
    assert(cFile["class"] == "File");
    assert("location" in cFile);
    assert(cFile["location"] == "file:///foo/bar/buzz.txt");
    assert("basename" in cFile);
    assert(cFile["basename"] == "buzz.txt");
    assert("contents" !in cFile);
}

/// File literal
unittest
{
    import dyaml : Loader;

    enum lit = q"EOS
    class: File
    basename: created.txt
    contents: |
      foo
      bar
EOS";

    auto cFile = Loader.fromString(lit).load.toCanonicalFile;
    assert("class" in cFile);
    assert(cFile["class"] == "File");
    assert("basename" in cFile);
    assert(cFile["basename"] == "created.txt");
    assert("location" !in cFile);
    assert("contents" in cFile);
}

/// File object w/ secondaryFiles
unittest
{
}

///
auto downloadDirectory(Node dir, string dest, Wire wire, DownloadConfig config)
in(dir.type == NodeType.mapping)
in("class" in dir)
in(dir["class"] == "Directory")
in(dest.scheme == "file")
in(dest.path.exists)
{
    import std : absolutePath, array, buildPath, dirName, map, mkdir;

    auto cDir = dir.toCanonicalFile;
    string loc;
    auto listing = Node(YAMLNull());

    if (auto listing_ = "listing" in cDir)
    {
        import std.file : mkdir, write;

        // directory literal
        string bname;
        if (auto bn_ = "basename" in cDir)
        {
            bname = bn_.as!string;
        }
        else
        {
            import std : randomUUID;
            bname = randomUUID.toString;
        }
        auto destPath = buildPath(dest.path, bname);
        mkdir(destPath);
        loc = "file://"~destPath;

        listing = Node(listing_.sequence.map!(l => downloadParam(l, loc, wire, config)).array);
    }
    else
    {
        auto destURI = buildPath(dest, cDir["basename"].as!string);
        wire.downloadDirectory(cDir["location"].as!string, destURI);
        loc = destURI;
        // TODO: `listing` field in the case of CWL v1.0
    }

    Node ret = Node(cDir);
    ret["location"] = loc;
    ret["path"] = loc.path;
    if (listing.type != NodeType.null_)
    {
        ret["listing"] = listing;
    }
    return ret;
}

/// Directory w/o `listing` (file to file)
unittest
{
}

/// Directory w/ `listing` (file to file)
unittest
{
}

/**
 * Returns: A canonicalized Directory Node. That is,
 *   - Directory object in which `listing` and `basename` are available but `path` and `location` are not available
 *   - Directory object in which `location` and `basename` are available but `path` and `listing` are not available
 * Throws: Exception when `dir` is not valid Directory object.
 */
Node toCanonicalDirectory(Node dir)
in(dir.type == NodeType.mapping)
in("class" in dir)
in(dir["class"] == "Directory")
{
    import std : enforce;

    auto ret = Node(dir);
    auto path_ = "path" in dir;
    auto loc_ = "location" in dir;
    auto pwd = dir.startMark.name;

    if (path_ is null && loc_ is null)
    {
        // directory literal
        auto listing = enforce("listing" in dir);
        enforce(listing.type == NodeType.sequence);
    }
    else if (loc_ !is null)
    {
        ret["location"] = loc_.as!string.absoluteURI(pwd);
        ret.remove("path");
        ret.remove("listing");
    }
    else if (path_ !is null)
    {
        ret["location"] = path_.as!string.absoluteURI(pwd);
        ret.remove("path");
        ret.remove("listing");
    }

    if (auto bname = "basename" in dir)
    {
        import std : canFind;

        enforce(!bname.as!string.canFind("/"));
    }
    else if (auto p_ = "location" in ret)
    {
        import std : baseName;
        ret["basename"] = p_.as!string.path.baseName;
    }

    if (auto listing = "listing" in dir)
    {
        import std : array, map;

        auto canonicalizedListing = listing
            .sequence
            .map!((s)
            {
                auto class_ = enforce("class" in s).as!string;
                if (class_ == "File")
                {
                    return s.toCanonicalFile;
                }
                else if (class_ == "Directory")
                {
                    return s.toCanonicalDirectory;
                }
                throw new Exception("Unknown class: "~class_);
            })
            .array;
        ret["listing"] = canonicalizedListing;
    }
    return ret;
}

/// Directory object that indicates an actual directory
unittest
{
    import dyaml : Loader;

    enum lit = q"EOS
    class: Directory
    location: /foo/bar/buzz
EOS";

    auto cDir = Loader.fromString(lit).load.toCanonicalDirectory;

    assert("class" in cDir);
    assert(cDir["class"] == "Directory");
    assert("location" in cDir);
    assert(cDir["location"] == "file:///foo/bar/buzz");
    assert("basename" in cDir);
    assert(cDir["basename"] == "buzz");
}

/// Directory literal
unittest
{
}

/// Directory object w/ `listing`
unittest
{
}

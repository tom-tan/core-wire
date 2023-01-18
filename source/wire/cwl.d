/**
 * Authors: Tomoya Tanjo
 * Copyright: © 2022 Tomoya Tanjo
 * License: Apache-2.0
 */
module wire.cwl;

import dyaml;

import std : exists, isDir;

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
Node download(Node input, string destURI, Wire wire, DownloadConfig con) @safe
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
        // See_Also: https://github.com/dlang/phobos/blob/67d4521c2c53b4e8c4a5213860c49caf9396bde2/std/file.d#L4468
        () @trusted {
            foreach(string name; dirEntries(dir, SpanMode.shallow))
            {
                rename(name, buildPath(destPath, name.baseName));
            }
        }();
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
Node downloadParam(Node inp, string dest, Wire wire, DownloadConfig con) @safe
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
auto downloadFile(Node file, string dest, Wire wire, DownloadConfig config) @safe
in(file.type == NodeType.mapping)
in("class" in file)
in(file["class"] == "File")
in(dest.scheme == "file")
in(dest.path.exists)
in(dest.path.isDir)
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

///
auto downloadDirectory(Node dir, string dest, Wire wire, DownloadConfig config) @safe
in(dir.type == NodeType.mapping)
in("class" in dir)
in(dir["class"] == "Directory")
in(dest.scheme == "file")
in(dest.path.exists)
in(dest.path.isDir)
{
    return Node(dir);
}

/**
 * It converts a File node to a canonicalized File node.
 *
 * A canonicalized File node is:
 * - A File object that consists of `class`, `location`, `basename`, and `secondaryFiles` if available, or
 * - A File literal that consists of `class`, `contents`, and `secondaryFiles` if available.
 * This function leaves `format`, `checksum`, `size` and extension fields as is.
 * Any other fields are not available.
 *
 * Returns: A canonicalized File node. 
 * Throws: Exception when `file` is not a valid File object.
 */
Node toCanonicalFile(Node file) @safe
in(file.type == NodeType.mapping)
in("class" in file)
in(file["class"] == "File", "`File` is expected but actual: "~file["class"].as!string)
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
        // TODO: If `contents`` is set as a result of an Javascript expression, an `entry` in `InitialWorkDirRequirement`,
        // or read in from `cwl.output.json`, there is no specified upper limit on the size of `contents`.
        enforce(con.as!string.length <= 64*2^^10);
    }
    else if (loc_ !is null)
    {
        ret["location"] = loc_.as!string.absoluteURI(pwd);
        ret.removeAt("contents"); // TODO
    }
    else if (path_ !is null)
    {
        ret["location"] = path_.as!string.absoluteURI(pwd);
        ret.removeAt("contents"); // TODO
    }

    if (auto bname = "basename" in ret)
    {
        import std : canFind;

        enforce(!bname.as!string.canFind("/"));
    }
    else if (auto p_ = "location" in ret)
    {
        if (auto l_ = "location" in ret)
        {
            import std : baseName;
            ret["basename"] = l_.as!string.path.baseName;
        }
    }

    ret.removeAt("path");
    ret.removeAt("dirname");
    ret.removeAt("nameroot");
    ret.removeAt("nameext");

    if (auto sec = "secondaryFiles" in file)
    {
        import std : array, empty, map;

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

        if (canonicalizedSec.empty)
        {
            ret.removeAt("secondaryFiles");
        }
        else
        {
            ret["secondaryFiles"] = canonicalizedSec;
        }
    }

    return ret;
}

///
@safe unittest
{
    enum origYAML = q"EOS
        class: File
        path: /foo/bar/buzz.txt
        ext:field: "This is an extension field."
EOS";

    auto origFile = Loader.fromString(origYAML).load.toCanonicalFile;
    assert(origFile.length == 4);
    assert(origFile["class"] == "File");
    assert(origFile["location"] == "file:///foo/bar/buzz.txt");
    assert(origFile["basename"] == "buzz.txt");
    assert(origFile["ext:field"] == "This is an extension field.");
}

///
@safe unittest
{
    enum origYAML = q"EOS
        class: File
        contents: |
            foo
            bar
EOS";

    auto origFile = Loader.fromString(origYAML).load.toCanonicalFile;
    assert(origFile.length == 2);
    assert(origFile["class"] == "File");
    assert(origFile["contents"] == "foo\nbar\n");
}

/**
 * Returns: A canonicalized Directory Node. That is,
 *   - Directory object in which `listing` and `basename` are available but `path` and `location` are not available, or
 *   - Directory object in which `location` and `basename` are available but `path` and `listing` are not available
 * Throws: Exception when `dir` is not valid Directory object.
 */
Node toCanonicalDirectory(Node dir) @safe
in(dir.type == NodeType.mapping)
in("class" in dir)
in(dir["class"] == "Directory", "`Directory` is expected but actual: "~dir["class"].as!string)
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
        ret.removeAt("listing");
    }
    else if (path_ !is null)
    {
        ret["location"] = path_.as!string.absoluteURI(pwd);
        ret.removeAt("listing");
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

    ret.removeAt("path");

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

///
@safe unittest
{
    import std : to;
    enum origYAML = q"EOS
        class: Directory
        path: /foo/bar/buzzDir
        ext:field: "This is an extension field."
EOS";

    auto origFile = Loader.fromString(origYAML).load.toCanonicalDirectory;
    assert(origFile.length == 4, "Actual: "~origFile.length.to!string);
    assert(origFile["class"] == "Directory");
    assert(origFile["location"] == "file:///foo/bar/buzzDir");
    assert(origFile["basename"] == "buzzDir");
    assert(origFile["ext:field"] == "This is an extension field.");
}

///
@safe unittest
{
    enum origYAML = q"EOS
        class: Directory
        listing:
          - class: File
            contents: |
              foo
          - class: File
            contents: |
              bar
EOS";

    auto origFile = Loader.fromString(origYAML).load.toCanonicalDirectory;
    assert(origFile.length == 2);
    assert(origFile["class"] == "Directory");
    assert(origFile["listing"].length == 2);
    assert(origFile["listing"][0].length == 2);
    assert(origFile["listing"][0]["class"] == "File");
    assert(origFile["listing"][0]["contents"] == "foo\n");
    assert(origFile["listing"][1].length == 2);
    assert(origFile["listing"][1]["class"] == "File");
    assert(origFile["listing"][1]["contents"] == "bar\n");
}

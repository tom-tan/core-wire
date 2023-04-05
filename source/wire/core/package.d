/**
 * Authors: Tomoya Tanjo
 * Copyright: © 2022 Tomoya Tanjo
 * License: Apache-2.0
 */
module wire.core;

import std.algorithm : canFind;
import std.file : exists, isDir, isFile;
import std.path : dirName;

import wire.util : path, scheme;

///
enum CoreWireType : ubyte
{
    none = 0b00,
    up   = 0b01,
    down = 0b10,
    both = up | down,
}

///
abstract class CoreWire
{
    ///
    void downloadFile(string src, string dst) const @safe
    in(dst.scheme == "file")
    in(schemes.canFind(src.scheme))
    in(dst.path.dirName.exists && dst.path.dirName.isDir)
    out(;dst.path.exists && dst.path.isFile);

    ///
    void downloadDirectory(string src, string dst) const @safe
    in(dst.scheme == "file")
    in(schemes.canFind(src.scheme))
    in(dst.path.dirName.exists && dst.path.dirName.isDir)
    out(;dst.path.exists && dst.path.isDir)
    {
        import std : format;
        import wire.exception : UnsupportedFeature;

        auto s = src.scheme;
        throw new UnsupportedFeature(format!"CoreWire for `%s` does not support downloading directory"(s));
    }

    ///
    void uploadDirectory(string src, string dst) const @safe
    in(src.scheme == "file")
    in(schemes.canFind(dst.scheme))
    in(src.path.exists && src.path.isDir);

    ///
    final bool support(string scheme) const @safe
    {
        return schemes.canFind(scheme);
    }

    ///
    bool supportDownloadDirectory() const @safe;

    ///
    CoreWireType type() const @safe;

protected:
    const(string[]) schemes() const @safe;
}

///
interface CoreWireConfig
{
}

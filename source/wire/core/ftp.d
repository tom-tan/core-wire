/**
 * Authors: Tomoya Tanjo
 * Copyright: © 2022 Tomoya Tanjo
 * License: Apache-2.0
 */
module wire.core.ftp;

import wire.core : CoreWire, CoreWireConfig, CoreWireType;

///
class FTPCoreWire : CoreWire
{
    ///
    this(CoreWireConfig config = null) @safe
    {
    }

    ///
    override void downloadFile(string src, string dst) const @trusted
    {
        version(none)
        {
            // https://github.com/ikod/dlang-requests/issues/150
            import wire.exception : ResourceError;
            import wire.util : path;
            import requests;

            import std : copy, File, seconds;

            auto rq = Request();
            rq.useStreaming = true;
            auto rs = rq.get(src);

            auto dstFile = File(dst.path, "wb");
            rs.receiveAsRange()
              .copy(dstFile.lockingBinaryWriter);
            // TODO: handling ResourceEror such as no network connections etc.
        }
        import wire.exception : ResourceError, UnsupportedFeature;
        import wire.util : path;
        import std : enforce, execute, executeShell, format;

        auto r = execute(["which", "curl"]);
        enforce!UnsupportedFeature(r.status == 0, "`curl` not found to download `ftp` resources");

        auto ret = execute(["curl", "-f", src, "-o", dst.path]);
        enforce!ResourceError(
            ret.status == 0,
            format!"Download `%s` failed with the following message: `%s`"(src, ret.output)
        );

    }

    ///
    override void uploadDirectory(string src, string dst) const @safe
    {
        assert(false, "Not yet implemented");
    }

    ///
    override bool supportDownloadDirectory() const @safe
    {
        return false; // not yet implemented
    }

    ///
    override CoreWireType type() const @safe
    {
        return CoreWireType.down;
    }

protected:
    override string[] schemes() const nothrow pure @safe
    {
        return ["ftp"];
    }
}

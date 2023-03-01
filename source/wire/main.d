/**
 * Authors: Tomoya Tanjo
 * Copyright: © 2022 Tomoya Tanjo
 * License: Apache-2.0
 */
module wire.main;

///
int wireMain(string[] args)
{
    import dyaml : Loader;
    import std;
    import wire : defaultWire;
    import wire.cwl : download, upload, DownloadConfig;
    import wire.util : absoluteURI, scheme, toJSON;

    string destURI;
    string configFile;
    DownloadConfig con;

    auto opts = args.getopt(
        config.caseSensitive,
        config.required,
        "dest", "Destination base URI",  (string opt, string uri) { destURI = uri.absoluteURI; },
        "randomize", "Make ramdomized subdirectory for each File or Directory", &con.makeRandomDir,
        "config", "Configuration file", &configFile,
    );

    if (opts.helpWanted || args.length != 2)
    {
        immutable baseMessage = format!(q"EOS
            core-wire: A tool/library to make CWL engines connected to remote resources
            Usage: %s [options] src.yml
EOS".outdent[0 .. $ - 1])(args[0].baseName);

        defaultGetoptFormatter(
            stdout.lockingTextWriter, baseMessage,
            opts.options, "%-*s %-*s%*s%s\x0a",
        );
        return 0;
    }

    auto inpFile = args[1].absolutePath;

    enforce(inpFile.exists && inpFile.isFile);
    auto loader = Loader.fromFile(inpFile);
    loader.name = "file://"~inpFile;

    auto node = loader.load;

    auto staged = destURI.scheme == "file"
        ? download(node, destURI, defaultWire, con)
        : upload(node, destURI, defaultWire);

    writeln(staged.toJSON);
    return 0;
}

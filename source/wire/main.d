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
    import wire.cwl : staging;

    string destURI;
    string configFile;

    auto opts = args.getopt(
        config.caseSensitive,
        config.required,
        "dest", "Destination base URI",  &destURI,
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
    auto staged = node.staging(destURI, null);

    import wire.util : toJSON;
    writeln(staged.toJSON);
    return 0;
}

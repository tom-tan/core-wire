/**
 * Authors: Tomoya Tanjo
 * Copyright: © 2022 Tomoya Tanjo
 * License: Apache-2.0
 */
module wire.exception;

import std.exception : basicExceptionCtors;

///
abstract class WireException : Exception
{
    mixin basicExceptionCtors;
}

/// input file or directory not found
class InputNotFound : WireException
{
    mixin basicExceptionCtors;
}

/// resource cannot be uploaded or downloaded
class ResourceError : WireException
{
    mixin basicExceptionCtors;
}

/// invalid input object
class InvalidInput : WireException
{
    mixin basicExceptionCtors;
}

/// unsupported feature
class UnsupportedFeature : WireException
{
    mixin basicExceptionCtors;
}

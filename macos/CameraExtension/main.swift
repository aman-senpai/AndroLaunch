//
//  main.swift
//  AndroLaunch Camera Extension
//
//  CMIO system-extension entry point. This executable is installed inside the
//  host app at Contents/Library/SystemExtensions and activated with
//  OSSystemExtensionRequest. It exposes a virtual camera so the local signing
//  path can be tested end-to-end before Android frames are piped in.
//

import CoreMediaIO
import Foundation

let providerSource = AndroLaunchCameraProviderSource()
CMIOExtensionProvider.startService(provider: providerSource.provider)
CFRunLoopRun()

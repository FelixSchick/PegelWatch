//
//  MyPegel.swift
//  MyPegel
//
//  Created by Felix Schick on 24.03.26.
//

import ExtensionFoundation
import Foundation
import ContactProvider

@main
class MyPegel: ContactProviderExtension {
    private let rootContainerEnumerator: MyPegelRootContainerEnumerator

    required init() {
        // Initialize your extension here.
        rootContainerEnumerator = MyPegelRootContainerEnumerator()
    }

    func configure(for domain: ContactProviderDomain) {
        // Configure your extension here.
        rootContainerEnumerator.configure(for: domain)
    }

    func enumerator(for collection: ContactItem.Identifier) -> ContactItemEnumerator {
        return rootContainerEnumerator
    }

    func invalidate() async throws {
        // TODO: Stop any enumeration and cleanup as the extension will be terminated.
    }
}

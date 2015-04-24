//
//  YapDBExtensionsMobileTests.swift
//  YapDBExtensionsMobileTests
//
//  Created by Daniel Thorpe on 15/04/2015.
//  Copyright (c) 2015 Daniel Thorpe. All rights reserved.
//

import UIKit
import XCTest
import YapDatabase
import YapDatabaseExtensions
import YapDBExtensionsMobile

class YapDBTests: XCTestCase {

    func test_ViewRegistration_NotRegisteredInEmptyDatabase() {
        let db = createYapDatabase(__FILE__, suffix: __FUNCTION__)
        let fetch: YapDB.Fetch = products()
        XCTAssertFalse(fetch.isRegisteredInDatabase(db), "Extension should not be registered in fresh database.")
    }

    func test_ViewRegistration_RegistersCorrectly() {
        let db = createYapDatabase(__FILE__, suffix: __FUNCTION__)
        let fetch: YapDB.Fetch = products()
        fetch.registerInDatabase(db)
        XCTAssertTrue(fetch.isRegisteredInDatabase(db), "Extension should be registered in database.")
    }

    func test_AfterRegistration_ViewIsAccessible() {
        let db = createYapDatabase(__FILE__, suffix: __FUNCTION__)
        let fetch: YapDB.Fetch = products()
        fetch.registerInDatabase(db)
        db.newConnection().read { transaction in
            XCTAssertNotNil(transaction.ext(fetch.name) as? YapDatabaseViewTransaction, "The view should be accessible inside a read transaction.")
        }
    }
}


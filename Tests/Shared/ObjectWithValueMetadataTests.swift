//
//  ObjectWithValueMetadataTests.swift
//  YapDatabaseExtensions
//
//  Created by Daniel Thorpe on 09/10/2015.
//  Copyright © 2015 Daniel Thorpe. All rights reserved.
//

import Foundation
import XCTest
@testable import YapDatabaseExtensions

class ObjectWithValueMetadataTests: XCTestCase {

    var item: Manager!
    var index: YapDB.Index!
    var key: String!

    var items: [Manager]!
    var indexes: [YapDB.Index]!
    var keys: [String]!

    var database: TestableDatabase!
    var connection: TestableConnection!
    var writeTransaction: TestableWriteTransaction!
    var readTransaction: TestableReadTransaction!

    var reader: Read<Manager, TestableDatabase>!
    var writer: Write<Manager, TestableDatabase>!

    var dispatchQueue: dispatch_queue_t!
    var operationQueue: NSOperationQueue!

    override func setUp() {
        super.setUp()
        createPersistables()
        index = item.index
        key = item.key

        indexes = items.map { $0.index }
        keys = items.map { $0.key }

        database = TestableDatabase()
        connection = TestableConnection()
        writeTransaction = TestableWriteTransaction()
        readTransaction = TestableReadTransaction()

        connection.readTransaction = readTransaction
        connection.writeTransaction = writeTransaction
        database.connection = connection

        dispatchQueue = dispatch_get_global_queue(QOS_CLASS_DEFAULT, 0)
        operationQueue = NSOperationQueue()
    }

    override func tearDown() {
        item = nil
        index = nil
        key = nil
        items = nil
        indexes = nil
        keys = nil

        database = nil
        connection = nil
        writeTransaction = nil
        readTransaction = nil
        dispatchQueue = nil
        operationQueue = nil
        super.tearDown()
    }

    func createPersistables() {
        item = Manager(id: "beatle-1", name: "John")
        item.metadata = Manager.Metadata(numberOfDirectReports: 4)
        items = [
            item,
            Manager(id: "beatle-2", name: "Paul"),
            Manager(id: "beatle-3", name: "George"),
            Manager(id: "beatle-4", name: "Ringo")
        ]
        items.suffixFrom(1).forEach { $0.metadata = Manager.Metadata(numberOfDirectReports: 1) }
    }

    func configureForReadingSingle() {
        readTransaction.object = item
    }

    func configureForReadingMultiple() {
        readTransaction.objects = items
        readTransaction.keys = keys
    }

    // MARK: Tests

    // Writing

    func test__writer_initializes_with_single_item() {
        writer = Write(item)

        XCTAssertEqual(writer.items.first!.identifier, item.identifier)
    }

    func test__writer_initializes_with_multiple_items() {
        writer = Write(items)

        XCTAssertEqual(writer.items.map { $0.key }, keys)
    }

    func test__write_on_transaction() {
        writer = Write(item)
        writer.on(writeTransaction)

        XCTAssertFalse(writeTransaction.didWriteAtIndexes.isEmpty)
        XCTAssertEqual(writeTransaction.didWriteAtIndexes[0].0, index)
        XCTAssertEqual(writeTransaction.didWriteAtIndexes[0].1.identifier, item.identifier)
        XCTAssertEqual(Manager.MetadataType.decode(writeTransaction.didWriteAtIndexes[0].2), item.metadata)
    }

    func test__write_sync() {
        writer = Write(item)
        writer.sync(connection)

        XCTAssertTrue(connection.didWrite)
        XCTAssertFalse(writeTransaction.didWriteAtIndexes.isEmpty)
        XCTAssertEqual(writeTransaction.didWriteAtIndexes[0].0, index)
        XCTAssertEqual(writeTransaction.didWriteAtIndexes[0].1.identifier, item.identifier)
        XCTAssertEqual(Manager.MetadataType.decode(writeTransaction.didWriteAtIndexes[0].2), item.metadata)
    }

    func test__write_async() {
        let expectation = expectationWithDescription("Test: \(__FUNCTION__)")

        writer = Write(item)
        writer.async(connection, queue: dispatchQueue) {
            expectation.fulfill()
        }

        waitForExpectationsWithTimeout(3.0, handler: nil)
        XCTAssertTrue(connection.didAsyncWrite)
        XCTAssertFalse(connection.didWrite)
        XCTAssertFalse(writeTransaction.didWriteAtIndexes.isEmpty)
        XCTAssertEqual(writeTransaction.didWriteAtIndexes[0].0, index)
        XCTAssertEqual(writeTransaction.didWriteAtIndexes[0].1.identifier, item.identifier)
        XCTAssertEqual(Manager.MetadataType.decode(writeTransaction.didWriteAtIndexes[0].2), item.metadata)
    }

    func test__write_operation() {
        let expectation = expectationWithDescription("Test: \(__FUNCTION__)")

        writer = Write(item)
        let operation = writer.operation(connection)
        operation.completionBlock = {
            expectation.fulfill()
        }
        operationQueue.addOperation(operation)

        waitForExpectationsWithTimeout(3.0, handler: nil)
        XCTAssertTrue(connection.didWriteBlockOperation)
        XCTAssertFalse(connection.didWrite)
        XCTAssertFalse(connection.didAsyncWrite)
        XCTAssertFalse(writeTransaction.didWriteAtIndexes.isEmpty)
        XCTAssertEqual(writeTransaction.didWriteAtIndexes[0].0, index)
        XCTAssertEqual(writeTransaction.didWriteAtIndexes[0].1.identifier, item.identifier)
        XCTAssertEqual(Manager.MetadataType.decode(writeTransaction.didWriteAtIndexes[0].2), item.metadata)
    }

    // Reading - Internal

    func test__reader__in_transaction_at_index() {
        configureForReadingSingle()
        reader = Read(readTransaction)
        guard let item = reader.inTransaction(readTransaction, atIndex: index) else {
            XCTFail("Expecting to have an item"); return
        }
        XCTAssertEqual(readTransaction.didReadAtIndex!, index)
        XCTAssertEqual(item.identifier, item.identifier)
    }

    func test__reader__in_transaction_at_index_2() {
        configureForReadingSingle()
        reader = Read(readTransaction)
        let atIndex = reader.inTransactionAtIndex(readTransaction)
        guard let item = atIndex(index) else {
            XCTFail("Expecting to have an item"); return
        }
        XCTAssertEqual(readTransaction.didReadAtIndex!, index)
        XCTAssertEqual(item.identifier, item.identifier)
    }

    func test__reader__at_index_in_transaction() {
        configureForReadingSingle()
        reader = Read(readTransaction)
        let inTransaction = reader.atIndexInTransaction(index)
        guard let item = inTransaction(readTransaction) else {
            XCTFail("Expecting to have an item"); return
        }
        XCTAssertEqual(readTransaction.didReadAtIndex!, index)
        XCTAssertEqual(item.identifier, item.identifier)
    }

    func test__reader__at_indexes_in_transaction_with_items() {
        configureForReadingMultiple()
        reader = Read(readTransaction)
        let items = reader.atIndexesInTransaction(indexes)(readTransaction)
        XCTAssertEqual(readTransaction.didReadAtIndexes, indexes)
        XCTAssertEqual(items.map { $0.identifier }, items.map { $0.identifier })
    }

    func test__reader__at_indexes_in_transaction_with_no_items() {
        reader = Read(readTransaction)
        let items = reader.atIndexesInTransaction(indexes)(readTransaction)
        XCTAssertEqual(readTransaction.didReadAtIndexes, indexes)
        XCTAssertEqual(items, [])
    }

    func test__reader__in_transaction_by_key() {
        configureForReadingSingle()
        reader = Read(readTransaction)
        guard let item = reader.inTransaction(readTransaction, byKey: key) else {
            XCTFail("Expecting to have an item"); return
        }
        XCTAssertEqual(readTransaction.didReadAtIndex, index)
        XCTAssertEqual(item.identifier, item.identifier)
    }

    func test__reader__in_transaction_by_key_2() {
        configureForReadingSingle()
        reader = Read(readTransaction)
        let byKey = reader.inTransactionByKey(readTransaction)
        guard let item = byKey(key) else {
            XCTFail("Expecting to have an item"); return
        }
        XCTAssertEqual(readTransaction.didReadAtIndex, index)
        XCTAssertEqual(item.identifier, item.identifier)
    }

    func test__reader__by_key_in_transaction() {
        configureForReadingSingle()
        reader = Read(readTransaction)
        let inTransaction = reader.byKeyInTransaction(key)
        guard let item = inTransaction(readTransaction) else {
            XCTFail("Expecting to have an item"); return
        }
        XCTAssertEqual(readTransaction.didReadAtIndex, index)
        XCTAssertEqual(item.identifier, item.identifier)
    }

    func test__reader__by_keys_in_transaction_with_items() {
        configureForReadingMultiple()
        reader = Read(readTransaction)
        let items = reader.byKeysInTransaction(keys)(readTransaction)
        XCTAssertEqual(readTransaction.didReadAtIndexes, indexes)
        XCTAssertEqual(items.map { $0.identifier }, items.map { $0.identifier })
    }

    func test__reader__by_keys_in_transaction_with_items_with_no_keys() {
        configureForReadingMultiple()
        reader = Read(readTransaction)
        let items = reader.byKeysInTransaction()(readTransaction)
        XCTAssertEqual(readTransaction.didReadAtIndexes, indexes)
        XCTAssertEqual(readTransaction.didKeysInCollection!, Manager.collection)
        XCTAssertEqual(items.map { $0.identifier }, items.map { $0.identifier })
    }

    func test__reader__by_keys_in_transaction_with_no_items() {
        reader = Read(readTransaction)
        let items = reader.byKeysInTransaction(keys)(readTransaction)
        XCTAssertEqual(readTransaction.didReadAtIndexes, indexes)
        XCTAssertEqual(items, [])
    }

    // Reading - With Transaction

    func test__reader_with_transaction__at_index_with_item() {
        configureForReadingSingle()
        reader = Read(readTransaction)
        guard let item = reader.atIndex(index) else {
            XCTFail("Expecting to have an item"); return
        }
        XCTAssertEqual(readTransaction.didReadAtIndex!, index)
        XCTAssertEqual(item.identifier, item.identifier)
    }

    func test__reader_with_transaction__at_index_with_no_item() {
        reader = Read(readTransaction)
        let item = reader.atIndex(index)
        XCTAssertEqual(readTransaction.didReadAtIndex!, index)
        XCTAssertNil(item)
    }

    func test__reader_with_transaction__at_indexes_with_items() {
        configureForReadingMultiple()
        reader = Read(readTransaction)
        let items = reader.atIndexes(indexes)
        XCTAssertEqual(readTransaction.didReadAtIndexes, indexes)
        XCTAssertEqual(items.map { $0.identifier }, items.map { $0.identifier })
    }

    func test__reader_with_transaction__at_indexes_with_no_items() {
        reader = Read(readTransaction)
        let items = reader.atIndexes(indexes)
        XCTAssertEqual(readTransaction.didReadAtIndexes, indexes)
        XCTAssertEqual(items, [])
    }

    func test__reader_with_transaction__by_key_with_item() {
        configureForReadingSingle()
        reader = Read(readTransaction)
        guard let item = reader.byKey(key) else {
            XCTFail("Expecting to have an item"); return
        }
        XCTAssertEqual(readTransaction.didReadAtIndex!, index)
        XCTAssertEqual(item.identifier, item.identifier)
    }

    func test__reader_with_transaction__by_key_with_no_item() {
        reader = Read(readTransaction)
        let item = reader.byKey(key)
        XCTAssertEqual(readTransaction.didReadAtIndex!, index)
        XCTAssertNil(item)
    }

    func test__reader_with_transaction__by_keys_with_items() {
        configureForReadingMultiple()
        reader = Read(readTransaction)
        let items = reader.byKeys(keys)
        XCTAssertEqual(readTransaction.didReadAtIndexes, indexes)
        XCTAssertEqual(items.map { $0.identifier }, items.map { $0.identifier })
    }

    func test__reader_with_transaction__by_keys_with_no_items() {
        reader = Read(readTransaction)
        let items = reader.byKeys(keys)
        XCTAssertEqual(readTransaction.didReadAtIndexes, indexes)
        XCTAssertEqual(items, [])
    }

    func test__reader_with_transaction__all_with_items() {
        configureForReadingMultiple()
        reader = Read(readTransaction)
        let items = reader.all()
        XCTAssertEqual(readTransaction.didKeysInCollection, Manager.collection)
        XCTAssertEqual(readTransaction.didReadAtIndexes, indexes)
        XCTAssertEqual(items.map { $0.identifier }, items.map { $0.identifier })
    }

    func test__reader_with_transaction__all_with_no_items() {
        reader = Read(readTransaction)
        let items = reader.all()
        XCTAssertEqual(readTransaction.didKeysInCollection, Manager.collection)
        XCTAssertEqual(readTransaction.didReadAtIndexes, [])
        XCTAssertEqual(items, [])
    }

    func test__reader_with_transaction__filter() {
        configureForReadingSingle()
        reader = Read(readTransaction)
        let (items, missing) = reader.filterExisting(keys)
        XCTAssertEqual(readTransaction.didReadAtIndexes.first!, indexes.first!)
        XCTAssertEqual(items.map { $0.identifier }, items.prefixUpTo(1).map { $0.identifier })
        XCTAssertEqual(missing, Array(keys.suffixFrom(1)))
    }

    // Reading - With Connection

    func test__reader_with_connection__at_index_with_item() {
        configureForReadingSingle()
        reader = Read(connection)
        guard let item = reader.atIndex(index) else {
            XCTFail("Expecting to have an item"); return
        }
        XCTAssertTrue(connection.didRead)
        XCTAssertEqual(readTransaction.didReadAtIndex!, index)
        XCTAssertEqual(item.identifier, item.identifier)
    }

    func test__reader_with_connection__at_index_with_no_item() {
        reader = Read(connection)
        let item = reader.atIndex(index)
        XCTAssertTrue(connection.didRead)
        XCTAssertEqual(readTransaction.didReadAtIndex!, index)
        XCTAssertNil(item)
    }

    func test__reader_with_connection__at_indexes_with_items() {
        configureForReadingMultiple()
        reader = Read(connection)
        let items = reader.atIndexes(indexes)
        XCTAssertTrue(connection.didRead)
        XCTAssertEqual(readTransaction.didReadAtIndexes, indexes)
        XCTAssertEqual(items.map { $0.identifier }, items.map { $0.identifier })
    }

    func test__reader_with_connection__at_indexes_with_no_items() {
        reader = Read(connection)
        let items = reader.atIndexes(indexes)
        XCTAssertTrue(connection.didRead)
        XCTAssertEqual(readTransaction.didReadAtIndexes, indexes)
        XCTAssertEqual(items, [])
    }

    func test__reader_with_connection__by_key_with_item() {
        configureForReadingSingle()
        reader = Read(connection)
        guard let item = reader.byKey(key) else {
            XCTFail("Expecting to have an item"); return
        }
        XCTAssertTrue(connection.didRead)
        XCTAssertEqual(readTransaction.didReadAtIndex!, index)
        XCTAssertEqual(item.identifier, item.identifier)
    }

    func test__reader_with_connection__by_key_with_no_item() {
        reader = Read(connection)
        let item = reader.byKey(key)
        XCTAssertTrue(connection.didRead)
        XCTAssertEqual(readTransaction.didReadAtIndex!, index)
        XCTAssertNil(item)
    }

    func test__reader_with_connection__by_keys_with_items() {
        configureForReadingMultiple()
        reader = Read(connection)
        let items = reader.byKeys(keys)
        XCTAssertTrue(connection.didRead)
        XCTAssertEqual(readTransaction.didReadAtIndexes, indexes)
        XCTAssertEqual(items.map { $0.identifier }, items.map { $0.identifier })
    }

    func test__reader_with_connection__by_keys_with_no_items() {
        reader = Read(connection)
        let items = reader.byKeys(keys)
        XCTAssertTrue(connection.didRead)
        XCTAssertEqual(readTransaction.didReadAtIndexes, indexes)
        XCTAssertEqual(items, [])
    }

    func test__reader_with_connection__all_with_items() {
        configureForReadingMultiple()
        reader = Read(connection)
        let items = reader.all()
        XCTAssertTrue(connection.didRead)
        XCTAssertEqual(readTransaction.didKeysInCollection, Manager.collection)
        XCTAssertEqual(readTransaction.didReadAtIndexes, indexes)
        XCTAssertEqual(items.map { $0.identifier }, items.map { $0.identifier })
    }

    func test__reader_with_connection__all_with_no_items() {
        reader = Read(connection)
        let items = reader.all()
        XCTAssertTrue(connection.didRead)
        XCTAssertEqual(readTransaction.didKeysInCollection, Manager.collection)
        XCTAssertEqual(readTransaction.didReadAtIndexes, [])
        XCTAssertEqual(items, [])
    }

    func test__reader_with_connection__filter() {
        configureForReadingSingle()
        reader = Read(connection)
        let (items, missing) = reader.filterExisting(keys)
        XCTAssertTrue(connection.didRead)
        XCTAssertEqual(readTransaction.didReadAtIndexes.first!, indexes.first!)
        XCTAssertEqual(items.map { $0.identifier }, items.prefixUpTo(1).map { $0.identifier })
        XCTAssertEqual(missing, Array(keys.suffixFrom(1)))
    }


    // Functional API - ReadTransactionType - Reading

    func test__transaction__read_at_index_with_data() {
        configureForReadingSingle()
        let manager: Manager? = readTransaction.readAtIndex(index)
        XCTAssertNotNil(manager)
        XCTAssertEqual(manager!.identifier, item.identifier)
    }

    func test__transaction__read_at_index_without_data() {
        let manager: Manager? = readTransaction.readAtIndex(index)
        XCTAssertNil(manager)
    }

    func test__transaction__read_at_indexes_with_data() {
        configureForReadingMultiple()
        let managers: [Manager] = readTransaction.readAtIndexes(indexes)
        XCTAssertEqual(managers.count, items.count)
    }

    func test__transaction__read_at_indexes_without_data() {
        let managers: [Manager] = readTransaction.readAtIndexes(indexes)
        XCTAssertNotNil(managers)
        XCTAssertTrue(managers.isEmpty)
    }

    func test__transaction__read_by_key_with_data() {
        configureForReadingSingle()
        let manager: Manager? = readTransaction.readByKey(key)
        XCTAssertNotNil(manager)
        XCTAssertEqual(manager!.identifier, item.identifier)
    }

    func test__transaction__read_by_key_without_data() {
        let manager: Manager? = readTransaction.readByKey(key)
        XCTAssertNil(manager)
    }

    func test__transaction__read_by_keys_with_data() {
        configureForReadingMultiple()
        let managers: [Manager] = readTransaction.readByKeys(keys)
        XCTAssertEqual(managers.count, items.count)
    }

    func test__transaction__read_by_keys_without_data() {
        let managers: [Manager] = readTransaction.readByKeys(keys)
        XCTAssertNotNil(managers)
        XCTAssertTrue(managers.isEmpty)
    }

    // Functional API - ConnectionType - Reading

    func test__connection__read_at_index_with_data() {
        configureForReadingSingle()
        let manager: Manager? = connection.readAtIndex(index)
        XCTAssertNotNil(manager)
        XCTAssertEqual(manager!.identifier, item.identifier)
    }

    func test__connection__read_at_index_without_data() {
        let manager: Manager? = connection.readAtIndex(index)
        XCTAssertNil(manager)
    }

    func test__connection__read_at_indexes_with_data() {
        configureForReadingMultiple()
        let managers: [Manager] = connection.readAtIndexes(indexes)
        XCTAssertEqual(managers.count, items.count)
    }

    func test__connection__read_at_indexes_without_data() {
        let managers: [Manager] = connection.readAtIndexes(indexes)
        XCTAssertNotNil(managers)
        XCTAssertTrue(managers.isEmpty)
    }

    func test__connection__read_by_key_with_data() {
        configureForReadingSingle()
        let manager: Manager? = connection.readByKey(key)
        XCTAssertNotNil(manager)
        XCTAssertEqual(manager!.identifier, item.identifier)
    }

    func test__connection__read_by_key_without_data() {
        let manager: Manager? = connection.readByKey(key)
        XCTAssertNil(manager)
    }

    func test__connection__read_by_keys_with_data() {
        configureForReadingMultiple()
        let managers: [Manager] = connection.readByKeys(keys)
        XCTAssertEqual(managers.count, items.count)
    }

    func test__connection__read_by_keys_without_data() {
        let managers: [Manager] = connection.readByKeys(keys)
        XCTAssertNotNil(managers)
        XCTAssertTrue(managers.isEmpty)
    }

    // MARK: - Functional API - Transaction - Writing

    func test__transaction__write_item() {
        writeTransaction.write(item)

        XCTAssertFalse(writeTransaction.didWriteAtIndexes.isEmpty)
        XCTAssertEqual(writeTransaction.didWriteAtIndexes[0].0, index)
        XCTAssertEqual(writeTransaction.didWriteAtIndexes[0].1.identifier, item.identifier)
        XCTAssertEqual(Manager.MetadataType.decode(writeTransaction.didWriteAtIndexes[0].2), item.metadata)
    }

    func test__transaction__write_items() {
        writeTransaction.write(items)

        XCTAssertFalse(writeTransaction.didWriteAtIndexes.isEmpty)
        XCTAssertEqual(writeTransaction.didWriteAtIndexes.map { $0.0.key }.sort(), indexes.map { $0.key }.sort())
        XCTAssertEqual(writeTransaction.didWriteAtIndexes.map { $0.2 }.count, items.count)
    }

    // Functional API - Connection - Writing

    func test__connection__write_item() {
        connection.write(item)

        XCTAssertTrue(connection.didWrite)
        XCTAssertFalse(writeTransaction.didWriteAtIndexes.isEmpty)
        XCTAssertEqual(writeTransaction.didWriteAtIndexes[0].0, index)
        XCTAssertEqual(writeTransaction.didWriteAtIndexes[0].1.identifier, item.identifier)
        XCTAssertEqual(Manager.MetadataType.decode(writeTransaction.didWriteAtIndexes[0].2), item.metadata)
    }

    func test__connection__write_items() {
        connection.write(items)

        XCTAssertTrue(connection.didWrite)
        XCTAssertFalse(writeTransaction.didWriteAtIndexes.isEmpty)
        XCTAssertEqual(writeTransaction.didWriteAtIndexes.map { $0.0.key }.sort(), indexes.map { $0.key }.sort())
        XCTAssertEqual(writeTransaction.didWriteAtIndexes.map { $0.2 }.count, items.count)
    }

    func test__connection__async_write_item() {
        let expectation = expectationWithDescription("Test: \(__FUNCTION__)")
        connection.asyncWrite(item) { expectation.fulfill() }

        waitForExpectationsWithTimeout(3.0, handler: nil)
        XCTAssertTrue(connection.didAsyncWrite)
        XCTAssertFalse(writeTransaction.didWriteAtIndexes.isEmpty)
        XCTAssertEqual(writeTransaction.didWriteAtIndexes[0].0, index)
        XCTAssertEqual(writeTransaction.didWriteAtIndexes[0].1.identifier, item.identifier)
        XCTAssertEqual(Manager.MetadataType.decode(writeTransaction.didWriteAtIndexes[0].2), item.metadata)
    }

    func test__connection__async_write_items() {
        let expectation = expectationWithDescription("Test: \(__FUNCTION__)")
        connection.asyncWrite(items) { expectation.fulfill() }

        waitForExpectationsWithTimeout(3.0, handler: nil)
        XCTAssertTrue(connection.didAsyncWrite)
        XCTAssertFalse(writeTransaction.didWriteAtIndexes.isEmpty)
        XCTAssertEqual(writeTransaction.didWriteAtIndexes.map { $0.0.key }.sort(), indexes.map { $0.key }.sort())
        XCTAssertEqual(writeTransaction.didWriteAtIndexes.map { $0.2 }.count, items.count)
    }


}


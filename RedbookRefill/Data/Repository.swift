//
//  Repository.swift
//  RedPulse
//
//  Single read/write entry point on top of SwiftData's ModelContext.
//  All read APIs return materialised arrays (small dataset, no pagination).
//

import Foundation
import Observation
import SwiftData
import OSLog

private let log = Logger(subsystem: "com.redbook.refill", category: "Repository")

@Observable
@MainActor
final class Repository {
    let modelContext: ModelContext

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    // MARK: - Products

    func allProducts() -> [Product] {
        let descriptor = FetchDescriptor<Product>(
            sortBy: [SortDescriptor(\Product.createdAt, order: .reverse)]
        )
        return (try? modelContext.fetch(descriptor)) ?? []
    }

    @discardableResult
    func saveProduct(_ p: Product) -> Bool {
        if p.modelContext == nil {
            modelContext.insert(p)
        }
        do {
            try modelContext.save()
            log.info("Product saved: \(p.name)")
            return true
        } catch {
            log.error("Failed to save product \(p.name): \(error.localizedDescription)")
            return false
        }
    }

    @discardableResult
    func deleteProduct(_ p: Product) -> Bool {
        modelContext.delete(p)
        do {
            try modelContext.save()
            return true
        } catch {
            log.error("Failed to delete product \\(p.name): \\(error.localizedDescription)")
            return false
        }
    }

    // MARK: - Records

    func allRecords() -> [GenerationRecord] {
        let descriptor = FetchDescriptor<GenerationRecord>(
            sortBy: [SortDescriptor(\GenerationRecord.createdAt, order: .reverse)]
        )
        return (try? modelContext.fetch(descriptor)) ?? []
    }

    @discardableResult
    func saveRecord(_ r: GenerationRecord) -> Bool {
        if r.modelContext == nil {
            modelContext.insert(r)
        }
        do {
            try modelContext.save()
            log.info("Record saved")
            return true
        } catch {
            log.error("Failed to save record: \(error.localizedDescription)")
            return false
        }
    }

    @discardableResult
    func deleteRecord(_ r: GenerationRecord) -> Bool {
        modelContext.delete(r)
        do {
            try modelContext.save()
            return true
        } catch {
            log.error("Failed to delete record: \\(error.localizedDescription)")
            return false
        }
    }

    @discardableResult
    func clearAllRecords() -> Bool {
        let records = allRecords()
        for r in records {
            modelContext.delete(r)
        }
        do {
            try modelContext.save()
            return true
        } catch {
            log.error("Failed to clear all records: \\(error.localizedDescription)")
            return false
        }
    }

    // MARK: - Feedback

    @discardableResult
    func saveFeedback(_ f: Feedback) -> Bool {
        modelContext.insert(f)
        do {
            try modelContext.save()
            log.info("Feedback saved")
            return true
        } catch {
            log.error("Failed to save feedback: \\(error.localizedDescription)")
            return false
        }
    }

    // MARK: - Inspiration Items

    func allInspirationItems() -> [InspirationItem] {
        let descriptor = FetchDescriptor<InspirationItem>(
            sortBy: [SortDescriptor(\InspirationItem.createdAt, order: .reverse)]
        )
        return (try? modelContext.fetch(descriptor)) ?? []
    }

    @discardableResult
    func saveInspirationItem(_ item: InspirationItem) -> Bool {
        if item.modelContext == nil {
            modelContext.insert(item)
        }
        do {
            try modelContext.save()
            log.info("InspirationItem saved: \(item.title)")
            return true
        } catch {
            log.error("Failed to save inspiration item: \(error.localizedDescription)")
            return false
        }
    }

    @discardableResult
    func deleteInspirationItem(_ item: InspirationItem) -> Bool {
        modelContext.delete(item)
        do {
            try modelContext.save()
            return true
        } catch {
            log.error("Failed to delete inspiration item \\(item.title): \\(error.localizedDescription)")
            return false
        }
    }
}

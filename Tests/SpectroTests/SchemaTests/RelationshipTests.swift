import Foundation
import Testing
@testable import Spectro

@Suite("Relationships")
struct RelationshipTests {

    // MARK: - RelationshipInfo

    @Test("RelationshipInfo stores metadata")
    func relationshipInfoMetadata() {
        let info = RelationshipInfo(
            name: "posts",
            relatedTypeName: "Post",
            kind: .hasMany,
            foreignKey: "userId"
        )
        #expect(info.name == "posts")
        #expect(info.relatedTypeName == "Post")
        #expect(info.kind == .hasMany)
        #expect(info.foreignKey == "userId")
    }

    @Test("RelationshipInfo allows nil foreignKey")
    func relationshipInfoNilFK() {
        let info = RelationshipInfo(
            name: "profile",
            relatedTypeName: "Profile",
            kind: .hasOne,
            foreignKey: nil
        )
        #expect(info.foreignKey == nil)
    }

    // MARK: - SpectroLazyRelation State Machine

    @Test("SpectroLazyRelation starts as not loaded")
    func lazyRelationInitialState() {
        let relation = SpectroLazyRelation<[TestPost]>(
            relationshipInfo: RelationshipInfo(
                name: "posts", relatedTypeName: "TestPost",
                kind: .hasMany, foreignKey: nil
            )
        )
        #expect(!relation.isLoaded)
        #expect(relation.value == nil)
    }

    @Test("SpectroLazyRelation.withLoaded transitions to loaded state")
    func lazyRelationWithLoaded() {
        let relation = SpectroLazyRelation<[TestPost]>(
            relationshipInfo: RelationshipInfo(
                name: "posts", relatedTypeName: "TestPost",
                kind: .hasMany, foreignKey: nil
            )
        )
        let loaded = relation.withLoaded([])
        #expect(loaded.isLoaded)
        #expect(loaded.value != nil)
        #expect(loaded.value?.isEmpty == true)
    }

    @Test("SpectroLazyRelation preserves relationship info after loading")
    func lazyRelationPreservesInfo() {
        let info = RelationshipInfo(
            name: "posts", relatedTypeName: "TestPost",
            kind: .hasMany, foreignKey: "userId"
        )
        let relation = SpectroLazyRelation<[TestPost]>(relationshipInfo: info)
        let loaded = relation.withLoaded([])
        #expect(loaded.relationshipInfo.name == "posts")
        #expect(loaded.relationshipInfo.foreignKey == "userId")
    }

    @Test("SpectroLazyRelation default init")
    func lazyRelationDefaultInit() {
        let relation = SpectroLazyRelation<[TestPost]>()
        #expect(!relation.isLoaded)
    }

    // MARK: - Property Wrappers

    @Test("HasMany wrappedValue returns empty array when not loaded")
    func hasManyDefaultValue() {
        let wrapper = HasMany<TestPost>()
        #expect(wrapper.wrappedValue.isEmpty)
    }

    @Test("HasOne wrappedValue returns nil when not loaded")
    func hasOneDefaultValue() {
        let wrapper = HasOne<TestPost>()
        #expect(wrapper.wrappedValue == nil)
    }

    @Test("BelongsTo wrappedValue returns nil when not loaded")
    func belongsToDefaultValue() {
        let wrapper = BelongsTo<TestUser>()
        #expect(wrapper.wrappedValue == nil)
    }

    // MARK: - Conventional FK

    @Test("Conventional foreign key derivation")
    func conventionalForeignKey() {
        let fk = PreloadQuery<TestUser>.conventionalForeignKey(for: TestUser.self)
        #expect(fk == "testUserId")
    }
}

import PostgresKit
import XCTest

@testable import Spectro

struct PostSchema: Schema {
    static let schemaName = "posts"

    @SchemaBuilder
    static var fields: [SField] {
        Field.description("title", .string)
        Field.description("content", .string)
        Field.belongsTo(UserSchema.self)
        Field.description("created_at", .timestamp)
    }
}

final class PostgresRelationshipTests: XCTestCase {
    var database: TestDatabase!
    var repository: PostgresRepository!

    override func setUp() async throws {
        database = try TestDatabase()
        repository = PostgresRepository(pools: database.pools)

        try await repository.createTable(UserSchema.self)
        try await repository.createTable(PostSchema.self)
    }

    override func tearDown() async throws {
        try await repository.executeRaw("DROP TABLE IF EXISTS posts CASCADE;", [])
        try await repository.executeRaw("DROP TABLE IF EXISTS users CASCADE;", [])
        try await database.shutdown()
    }

    func testRelationshipInsertion() async throws {
        let userId = UUID()
        try await repository.insert(
            UserSchema.self,
            values: .with([
                "id": userId,
                "name": "John Doe",
                "email": "john@example.com",
            ]))

        for i in 1...3 {
            try await repository.insert(
                PostSchema.self,
                values: .with([
                    "id": UUID(),
                    "title": "Post \(i)",
                    "content": "Content \(i)",
                    "user_id": userId,
                    "created_at": Date(),
                ]))
        }

        let postsQuery = Query.from(PostSchema.self)
            .select { [$0.title, $0.content, $0.user_id] }
        let posts = try await repository.all(query: postsQuery)
        debugPrint(posts)
        XCTAssertEqual(posts.count, 3, "User should have 3 posts")
    }

    func testCascadeDelete() async throws {
        let userId = UUID()
        try await repository.insert(
            UserSchema.self,
            values: [
                "id": userId,
                "name": "Jane Doe",
                "email": "jane@example.com",
            ])

        try await repository.insert(
            PostSchema.self,
            values: [
                "title": "Test Post",
                "content": "Test Content",
                "user_id": userId,
                "created_at": Date(),
            ])

        try await repository.delete(from: "users", where: ["id": ("=", .uuid(userId))])

        let postsQuery = Query.from(PostSchema.self)
            .select { [$0.title] }
            .where { $0.user_id.eq(userId) }

        let posts = try await repository.all(query: postsQuery)
        XCTAssertEqual(posts.count, 0, "Posts should be deleted with user")
    }

    func testInvalidForeignKey() async throws {
        do {
            try await repository.insert(
                PostSchema.self,
                values: [
                    "id": UUID(),
                    "title": "Invalid Post",
                    "content": "This should fail",
                    "user_id": UUID(),
                    "created_at": Date(),
                ])
            XCTFail("Insert should fail with invalid foreign key")
        } catch {
            XCTAssertTrue(true, "Insert correctly failed with invalid foreign key")
        }
    }

    // func testRelationshipValidation() async throws {
    //     let userId = UUID()
    //     try await repository.insert(
    //         UserSchema.self,
    //         values: [
    //             "id": userId,
    //             "name": "Test User",
    //             "email": "test@example.com",
    //         ]
    //     )

    //     let postIds = try await withThrowingTaskGroup(of: UUID.self) { group in
    //         for i in 1...2 {
    //             group.addTask {
    //                 let postId = UUID()
    //                 try await self.repository.insert(
    //                     PostSchema.self,
    //                     values: [
    //                         "id": postId,
    //                         "title": "Post \(i)",
    //                         "content": "Content \(i)",
    //                         "user_id": userId,
    //                         "created_at": Date(),
    //                     ]
    //                 )
    //                 return postId
    //             }
    //         }

    //         var ids: [UUID] = []
    //         for try await id in group {
    //             ids.append(id)
    //         }
    //         return ids
    //     }

    //     let query = Query.from(UserSchema.self)
    //         .join(type: .left, table: "posts", on: "posts.user_id = users.id")
    //         .select { _ in
    //             [
    //                 "users.name",
    //                 "users.email",
    //                 "posts.title",
    //                 "posts.content",
    //             ]
    //         }
    //         .where { $0.id.eq(userId) }
    //         .orderBy { [$0.name.asc()] }

    //     let results = try await repository.all(query: query)

    //     XCTAssertEqual(results.count, 2, "Should find both posts for user")
    //     XCTAssertEqual(results[0].values["name"], "Test User")
    //     XCTAssertEqual(results[0].values["title"], "Post 1")
    //     XCTAssertEqual(results[1].values["title"], "Post 2")
    // }
}

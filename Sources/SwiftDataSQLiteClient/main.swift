import SwiftDataSQLite
import SwiftData
import Foundation

@SQLiteTable("authors")
@Model
class Author {
    var id: Int
    var name: String
    var country: String
    var photo: Data?
    @Relationship var books: [Book] = []
    init(id: Int, name: String, country: String, photo: Data? = nil) {
        self.id = id
        self.name = name
        self.country = country
        self.photo = photo
    }
}

@SQLiteTable("books")
@Model
class Book {
    var id: Int
    var name: String
    var year: Int
    @Relationship(inverse: \Author.books) var author: Author
    init(id: Int, name: String, year: Int, author: Author) {
        self.id = id
        self.name = name
        self.year = year
        self.author = author
    }
}

let modelContainer = try ModelContainer(for: Author.self, Book.self)

let modelContext = modelContainer.mainContext

let url = Bundle.module.url(forResource: "library", withExtension: "sqlite")!

do {
    try modelContext.loadFromSQLite([Author.self, Book.self], path: url.path(percentEncoded: false))
    
    let descriptor = FetchDescriptor<Author>(predicate: Predicate.true)
    let authors = try modelContext.fetch(descriptor)
    
    for author in authors {
        print(author.name)
        for book in author.books {
            print("\t", book.name)
        }
    }
} catch {
    print(error)
}

import Foundation
import SwiftData
import SwiftDataSQLite

// +----+---------------------+----------------+----------------------------------------------------------------------------+
// | id | name                | country        | genre                                                                      |
// +----+---------------------+----------------+----------------------------------------------------------------------------+
// | 1  | George R. R. Martin | United States  | ["fantasy","horror","science fiction"]                                     |
// | 2  | J. R. R. Tolkien    | United Kingdom | ["fantasy","high fantasy","mythopoeia","translation","literary criticism"] |
// +----+---------------------+----------------+----------------------------------------------------------------------------+


@SQLiteTable("authors")
@Model
class Author {
    var id: Int
    var name: String
    var country: String
    var photo: Data?
    var genre: [String]?
    @Relationship var books: [Book] = []
    init(id: Int, name: String, country: String, photo: Data? = nil, genre: [String]?) {
        self.id = id
        self.name = name
        self.country = country
        self.photo = photo
        self.genre = genre
        self.books = books
    }
}


// +----+----------------------------+------+-----------+
// | id | name                       | year | author_id |
// +----+----------------------------+------+-----------+
// | 1  | A Game of Thrones          | 1996 | 1         |
// | 2  | A Clash of Kings           | 1998 | 1         |
// | 3  | A Storm of Swords          | 2000 | 1         |
// | 4  | A Feast for Crows          | 2005 | 1         |
// | 5  | A Dance with Dragons       | 2011 | 1         |
// | 6  | The Hobbit                 | 1937 | 2         |
// | 7  | The Fellowship of the Ring | 1954 | 2         |
// | 8  | The Two Towers             | 1954 | 2         |
// | 9  | The Return of the King     | 1955 | 2         |
// +----+----------------------------+------+-----------+

@SQLiteTable("books")
@Model
class Book {
    @SQLiteColumn("ID")
    var id: Int
    @SQLiteColumn("name") var title: String
    var year: Int
    @Relationship(inverse: \Author.books) var author: Author
    init(id: Int, title: String, year: Int, author: Author) {
        self.id = id
        self.title = title
        self.year = year
        self.author = author
    }
}

let modelContainer = try ModelContainer(for: Author.self, Book.self)

let modelContext = modelContainer.mainContext

let path = Bundle.module.path(forResource: "library", ofType: "sqlite")!

do {
    try modelContext.loadFromSQLite([Author.self, Book.self], path: path)
    
    let descriptor = FetchDescriptor<Author>(predicate: Predicate.true)
    let authors = try modelContext.fetch(descriptor)
    
    for author in authors {
        print(author.name)
        print("country: \(author.country)")
        print("genre: \(author.genre ?? [])")
        print("books: \(author.books.map { "\($0.title) (\($0.year))" })")
    }
} catch {
    print(error)
}

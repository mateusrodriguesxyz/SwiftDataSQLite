//
//  Project.swift
//  SwiftDataSQLite
//
//  Created by Mateus Rodrigues on 12/06/26.
//

import Foundation
import SwiftData
import SwiftDataSQLite

@SQLiteTable("project")
@Model
class Project {
    var id: Int
    var name: String
    @Relationship var address: Address
    init(id: Int, name: String, address: Address) {
        self.id = id
        self.name = name
        self.address = address
    }
}


@SQLiteTable("addresses")
@Model
class Address {
    var id: Int
    var cep: String
    init(id: Int, cep: String) {
        self.id = id
        self.cep = cep
    }
}

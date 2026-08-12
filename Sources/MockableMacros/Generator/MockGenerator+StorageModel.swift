import SwiftSyntax
import SwiftSyntaxBuilder

// MARK: - Storage Model

extension MockGenerator {
    func hasTypeMembers() -> Bool {
        collectDeclsIncludingConditional().contains { Self.isTypeMember($0) }
    }

    static func isTypeMember(_ decl: DeclSyntax) -> Bool {
        if let funcDecl = decl.as(FunctionDeclSyntax.self) {
            return isTypeMember(funcDecl.modifiers)
        }

        if let varDecl = decl.as(VariableDeclSyntax.self) {
            return isTypeMember(varDecl.modifiers)
        }

        if let subscriptDecl = decl.as(SubscriptDeclSyntax.self) {
            return isTypeMember(subscriptDecl.modifiers)
        }

        return false
    }

    static func isTypeMember(_ modifiers: DeclModifierListSyntax) -> Bool {
        modifiers.contains { modifier in
            let modifierName = modifier.name.text
            return modifierName == "static" || modifierName == "class"
        }
    }

    static func typeMemberModifiers(isTypeMember: Bool) -> [DeclModifierSyntax] {
        guard isTypeMember else {
            return []
        }

        return [DeclModifierSyntax(name: .keyword(.static))]
    }

    static func storagePropertyName(isTypeMember: Bool) -> String {
        MockNaming.storageName(isTypeMember: isTypeMember)
    }

    var usesInstanceStorageLock: Bool {
        isActor || isSendable
    }

    func usesLockBasedStorage(isTypeMember: Bool) -> Bool {
        usesInstanceStorageLock || isTypeMember
    }
}

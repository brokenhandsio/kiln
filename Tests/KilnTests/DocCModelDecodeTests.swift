import Testing
import Foundation
@testable import Kiln

/// Decodes the real Queues/XCTQueues DocC archives (checked in under
/// `Fixtures/docc`) with the lenient ``RenderNode`` model, asserting the whole
/// corpus round-trips with **zero** unrecognised constructs. This is the golden
/// guard against DocC render-JSON drift: if a future toolchain emits a construct
/// the model doesn't handle, this test surfaces it (as a recorded unknown) rather
/// than the model silently dropping content.
@Suite("DocC RenderNode decoding")
struct DocCModelDecodeTests {
    /// Locate the `Fixtures/docc` directory bundled with the test target.
    private func doccFixtures() throws -> URL {
        guard let fixtures = Bundle.module.url(forResource: "Fixtures", withExtension: nil) else {
            Issue.record("Could not locate the Fixtures resource")
            throw ContentError.contentDirectoryNotFound("Fixtures")
        }
        return fixtures.appendingPathComponent("docc")
    }

    /// All `data/**/*.json` RenderNode files in an archive.
    private func nodeFiles(in archive: URL) -> [URL] {
        let dataDir = archive.appendingPathComponent("data")
        guard let e = FileManager.default.enumerator(at: dataDir, includingPropertiesForKeys: nil) else { return [] }
        return e.compactMap { $0 as? URL }.filter { $0.pathExtension == "json" }.sorted { $0.path < $1.path }
    }

    private func decoder(_ diagnostics: DocCDiagnostics) -> JSONDecoder {
        let d = JSONDecoder()
        d.userInfo[.doccDiagnostics] = diagnostics
        return d
    }

    @Test("Every Queues + XCTQueues node decodes with zero unknown constructs")
    func decodesWholeCorpus() throws {
        let docc = try doccFixtures()
        let diagnostics = DocCDiagnostics()
        let dec = decoder(diagnostics)

        var total = 0
        for archive in ["Queues.doccarchive", "XCTQueues.doccarchive"] {
            let files = nodeFiles(in: docc.appendingPathComponent(archive))
            #expect(!files.isEmpty, "no node JSON found in \(archive)")
            for file in files {
                let data = try Data(contentsOf: file)
                do {
                    _ = try dec.decode(RenderNode.self, from: data)
                } catch {
                    Issue.record("Failed to decode \(archive)/\(file.lastPathComponent): \(error)")
                }
                total += 1
            }
        }

        // The whole queues corpus.
        #expect(total == 307, "expected 307 nodes, decoded \(total)")
        // The point of the test: nothing in this real corpus should be unrecognised.
        #expect(diagnostics.unknowns.isEmpty, "unexpected unknown DocC constructs: \(diagnostics.summary)")
    }

    @Test("Both index.json navigation trees decode")
    func decodesRenderIndex() throws {
        let docc = try doccFixtures()
        let diagnostics = DocCDiagnostics()
        let dec = decoder(diagnostics)

        let queuesIndex = docc.appendingPathComponent("Queues.doccarchive/index/index.json")
        let index = try dec.decode(RenderIndex.self, from: Data(contentsOf: queuesIndex))
        let roots = try #require(index.interfaceLanguages["swift"])
        let module = try #require(roots.first)
        #expect(module.title == "Queues")
        #expect(module.type == "module")
        #expect(module.path == "/documentation/queues")
        #expect((module.children?.isEmpty ?? true) == false)
        // A group marker is a non-navigable heading.
        #expect(module.children?.contains { $0.isGroupMarker } == true)

        // XCTQueues index too.
        let xctIndex = docc.appendingPathComponent("XCTQueues.doccarchive/index/index.json")
        _ = try dec.decode(RenderIndex.self, from: Data(contentsOf: xctIndex))
        #expect(diagnostics.unknowns.isEmpty)
    }

    @Test("A method node exposes its declaration, parameters, and resolved references")
    func decodesMethodNode() throws {
        let docc = try doccFixtures()
        let diagnostics = DocCDiagnostics()
        let file = docc.appendingPathComponent(
            "Queues.doccarchive/data/documentation/queues/queue/dispatch(_:_:maxretrycount:delayuntil:id:)-630ll.json")
        let node = try decoder(diagnostics).decode(RenderNode.self, from: Data(contentsOf: file))

        #expect(node.kind == .symbol)
        #expect(node.schemaVersion.major == 0 && node.schemaVersion.minor == 3)
        #expect(node.metadata.symbolKind == "method")
        #expect(node.metadata.title == "dispatch(_:_:maxRetryCount:delayUntil:id:)")

        let sections = try #require(node.primaryContentSections)
        // Declarations section with tokens.
        let declarations = sections.compactMap { section -> [RenderPrimarySection.Declaration]? in
            if case .declarations(let d) = section { return d }
            return nil
        }.first
        let decls = try #require(declarations)
        #expect(decls.first?.tokens.isEmpty == false)
        // At least one token links to another symbol (e.g. `Job`, `JobIdentifier`).
        #expect(decls.first?.tokens.contains { $0.identifier != nil } == true)

        // Parameters section, one entry per documented parameter.
        let parameters = sections.compactMap { section -> [RenderPrimarySection.ParameterDoc]? in
            if case .parameters(let p) = section { return p }
            return nil
        }.first
        let params = try #require(parameters)
        #expect(params.map(\.name) == ["job", "payload", "maxRetryCount", "delayUntil"])

        // References map resolves topic links with URLs.
        let refs = try #require(node.references)
        #expect(refs.values.contains { $0.topic?.url != nil })
        #expect(diagnostics.unknowns.isEmpty)
    }

    @Test("The module landing node decodes its discussion and topic groups")
    func decodesModuleLanding() throws {
        let docc = try doccFixtures()
        let diagnostics = DocCDiagnostics()
        let file = docc.appendingPathComponent("Queues.doccarchive/data/documentation/queues.json")
        let node = try decoder(diagnostics).decode(RenderNode.self, from: Data(contentsOf: file))

        #expect(node.metadata.symbolKind == "module" || node.metadata.role == "collection")
        // A discussion "content" section carrying a heading + list.
        let content = (node.primaryContentSections ?? []).compactMap { section -> [RenderBlockContent]? in
            if case .content(let blocks) = section { return blocks }
            return nil
        }.first
        let blocks = try #require(content)
        #expect(blocks.contains { if case .heading = $0 { return true } else { return false } })
        #expect(blocks.contains { if case .unorderedList = $0 { return true } else { return false } })

        // Curated topic groups with titles and members.
        let topics = try #require(node.topicSections)
        #expect(topics.isEmpty == false)
        #expect(topics.allSatisfy { !$0.identifiers.isEmpty })
        #expect(diagnostics.unknowns.isEmpty)
    }

    @Test("Unknown constructs decode to .unknown and are recorded, not thrown")
    func lenientOnUnknownConstructs() throws {
        // A synthetic node with an invented block type + inline type + section kind.
        let json = """
        {
          "schemaVersion": {"major": 0, "minor": 3, "patch": 0},
          "identifier": {"url": "doc://Test/documentation/Test/X", "interfaceLanguage": "swift"},
          "kind": "symbol",
          "metadata": {"title": "X"},
          "abstract": [{"type": "text", "text": "hi"}, {"type": "quantumGlyph", "text": "?"}],
          "primaryContentSections": [
            {"kind": "content", "content": [
              {"type": "paragraph", "inlineContent": [{"type": "text", "text": "ok"}]},
              {"type": "hologram", "foo": 1}
            ]},
            {"kind": "flux-capacitor", "stuff": true}
          ],
          "references": {}
        }
        """
        let diagnostics = DocCDiagnostics()
        let node = try decoder(diagnostics).decode(RenderNode.self, from: Data(json.utf8))
        #expect(node.metadata.title == "X")

        // Three distinct unknowns recorded, at the right locations.
        let summary = Set(diagnostics.summary)
        #expect(summary.contains("inline content: quantumGlyph"))
        #expect(summary.contains("block content: hologram"))
        #expect(summary.contains("primary content section: flux-capacitor"))
    }
}

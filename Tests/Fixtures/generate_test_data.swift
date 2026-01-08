#!/usr/bin/env swift
// MARK: - Test Data Generator
// Creates realistic test files for SortAI testing
// Usage: swift generate_test_data.swift

import Foundation

// MARK: - Configuration

let outputDir = "TestFiles"
let categories: [String: [TestFile]] = [
    "Documents": [
        // Reports
        TestFile(name: "Q4_2025_Financial_Report.pdf", type: .pdf, category: "Documents/Reports/Financial"),
        TestFile(name: "Annual_Performance_Review_2025.pdf", type: .pdf, category: "Documents/Reports/HR"),
        TestFile(name: "Market_Analysis_Tech_Sector.pdf", type: .pdf, category: "Documents/Reports/Business"),
        
        // Meeting Notes
        TestFile(name: "Team_Standup_Notes_2025-01-04.txt", type: .text, category: "Documents/Notes/Meetings"),
        TestFile(name: "Client_Meeting_Summary_Acme_Corp.txt", type: .text, category: "Documents/Notes/Meetings"),
        TestFile(name: "Product_Roadmap_Discussion.md", type: .markdown, category: "Documents/Notes/Planning"),
        
        // Contracts
        TestFile(name: "NDA_Template_2025.docx", type: .docx, category: "Documents/Legal/Contracts"),
        TestFile(name: "Service_Agreement_CloudHost.pdf", type: .pdf, category: "Documents/Legal/Contracts"),
        
        // Technical
        TestFile(name: "API_Documentation_v2.md", type: .markdown, category: "Documents/Technical/API"),
        TestFile(name: "System_Architecture_Overview.pdf", type: .pdf, category: "Documents/Technical/Architecture"),
        TestFile(name: "Database_Schema_ERD.pdf", type: .pdf, category: "Documents/Technical/Database"),
    ],
    
    "Media": [
        // Photos
        TestFile(name: "DSC_0001_Beach_Sunset.jpg", type: .jpeg, category: "Media/Photos/Vacation"),
        TestFile(name: "IMG_2024_Family_Reunion.jpg", type: .jpeg, category: "Media/Photos/Family"),
        TestFile(name: "Screenshot_2025-01-04_10-30-15.png", type: .png, category: "Media/Photos/Screenshots"),
        TestFile(name: "Product_Photo_Widget_A.png", type: .png, category: "Media/Photos/Products"),
        TestFile(name: "Team_Photo_Office_Party.jpg", type: .jpeg, category: "Media/Photos/Events"),
        
        // Videos
        TestFile(name: "Conference_Keynote_2025.mp4", type: .mp4, category: "Media/Videos/Conferences"),
        TestFile(name: "Product_Demo_Version_3.mp4", type: .mp4, category: "Media/Videos/Demos"),
        TestFile(name: "Screen_Recording_Bug_Report.mov", type: .mov, category: "Media/Videos/Screencasts"),
        TestFile(name: "Tutorial_Getting_Started.mp4", type: .mp4, category: "Media/Videos/Tutorials"),
        
        // Audio
        TestFile(name: "Podcast_Episode_42_AI_Future.mp3", type: .mp3, category: "Media/Audio/Podcasts"),
        TestFile(name: "Meeting_Recording_2025-01-03.m4a", type: .m4a, category: "Media/Audio/Recordings"),
        TestFile(name: "Background_Music_Chill_Lo-Fi.mp3", type: .mp3, category: "Media/Audio/Music"),
    ],
    
    "Code": [
        TestFile(name: "UserAuthService.swift", type: .swift, category: "Code/Swift/Services"),
        TestFile(name: "DatabaseMigration_v4.swift", type: .swift, category: "Code/Swift/Migrations"),
        TestFile(name: "api_handler.py", type: .python, category: "Code/Python/Backend"),
        TestFile(name: "data_analysis_notebook.ipynb", type: .jupyter, category: "Code/Python/Notebooks"),
        TestFile(name: "webpack.config.js", type: .javascript, category: "Code/JavaScript/Config"),
        TestFile(name: "UserDashboard.tsx", type: .typescript, category: "Code/TypeScript/Components"),
    ],
    
    "Data": [
        TestFile(name: "customer_data_export_2025.csv", type: .csv, category: "Data/Exports/Customers"),
        TestFile(name: "product_inventory.xlsx", type: .xlsx, category: "Data/Spreadsheets/Inventory"),
        TestFile(name: "api_response_sample.json", type: .json, category: "Data/API/Samples"),
        TestFile(name: "config_production.yaml", type: .yaml, category: "Data/Config/Production"),
        TestFile(name: "analytics_backup.sqlite", type: .sqlite, category: "Data/Databases/Backups"),
    ],
    
    "Archives": [
        TestFile(name: "project_backup_2025-01-01.zip", type: .zip, category: "Archives/Backups/Projects"),
        TestFile(name: "logs_december_2024.tar.gz", type: .targz, category: "Archives/Logs/Monthly"),
        TestFile(name: "old_design_assets.zip", type: .zip, category: "Archives/Assets/Design"),
    ],
    
    "Ebooks": [
        TestFile(name: "Swift_Programming_Guide.epub", type: .epub, category: "Ebooks/Technical/Programming"),
        TestFile(name: "Machine_Learning_Basics.pdf", type: .pdf, category: "Ebooks/Technical/AI"),
        TestFile(name: "Project_Management_Handbook.epub", type: .epub, category: "Ebooks/Business/Management"),
    ]
]

// MARK: - Test File Definition

struct TestFile {
    let name: String
    let type: FileType
    let category: String
    
    enum FileType {
        case pdf, text, markdown, docx
        case jpeg, png
        case mp4, mov
        case mp3, m4a
        case swift, python, javascript, typescript, jupyter
        case csv, xlsx, json, yaml, sqlite
        case zip, targz
        case epub
        
        var `extension`: String {
            switch self {
            case .pdf: return "pdf"
            case .text: return "txt"
            case .markdown: return "md"
            case .docx: return "docx"
            case .jpeg: return "jpg"
            case .png: return "png"
            case .mp4: return "mp4"
            case .mov: return "mov"
            case .mp3: return "mp3"
            case .m4a: return "m4a"
            case .swift: return "swift"
            case .python: return "py"
            case .javascript: return "js"
            case .typescript: return "tsx"
            case .jupyter: return "ipynb"
            case .csv: return "csv"
            case .xlsx: return "xlsx"
            case .json: return "json"
            case .yaml: return "yaml"
            case .sqlite: return "sqlite"
            case .zip: return "zip"
            case .targz: return "tar.gz"
            case .epub: return "epub"
            }
        }
    }
}

// MARK: - File Generators

class TestDataGenerator {
    let baseDir: URL
    
    init(outputDir: String) {
        let currentDir = FileManager.default.currentDirectoryPath
        self.baseDir = URL(fileURLWithPath: currentDir).appendingPathComponent(outputDir)
    }
    
    func generate() throws {
        // Create output directory
        try FileManager.default.createDirectory(at: baseDir, withIntermediateDirectories: true)
        
        // Generate all test files
        var generatedCount = 0
        for (_, files) in categories {
            for file in files {
                let url = baseDir.appendingPathComponent(file.name)
                try generateFile(file: file, at: url)
                generatedCount += 1
                print("✅ Created: \(file.name)")
            }
        }
        
        // Create category mapping file
        try createCategoryMapping()
        
        print("\n🎉 Generated \(generatedCount) test files in \(baseDir.path)")
    }
    
    private func generateFile(file: TestFile, at url: URL) throws {
        switch file.type {
        case .pdf:
            try generatePDF(name: file.name, at: url)
        case .text, .markdown:
            try generateText(name: file.name, category: file.category, at: url)
        case .docx:
            try generateDocx(name: file.name, at: url)
        case .jpeg:
            try generateJPEG(name: file.name, at: url)
        case .png:
            try generatePNG(name: file.name, at: url)
        case .mp4:
            try generateMP4(name: file.name, at: url)
        case .mov:
            try generateMOV(name: file.name, at: url)
        case .mp3:
            try generateMP3(name: file.name, at: url)
        case .m4a:
            try generateM4A(name: file.name, at: url)
        case .swift, .python, .javascript, .typescript:
            try generateCode(name: file.name, type: file.type, at: url)
        case .jupyter:
            try generateJupyter(name: file.name, at: url)
        case .csv:
            try generateCSV(name: file.name, at: url)
        case .xlsx:
            try generateXLSX(name: file.name, at: url)
        case .json:
            try generateJSON(name: file.name, at: url)
        case .yaml:
            try generateYAML(name: file.name, at: url)
        case .sqlite:
            try generateSQLite(name: file.name, at: url)
        case .zip:
            try generateZIP(name: file.name, at: url)
        case .targz:
            try generateTarGz(name: file.name, at: url)
        case .epub:
            try generateEPUB(name: file.name, at: url)
        }
    }
    
    // MARK: - Document Generators
    
    private func generatePDF(name: String, at url: URL) throws {
        // Minimal valid PDF
        let title = name.replacingOccurrences(of: "_", with: " ").replacingOccurrences(of: ".pdf", with: "")
        let content = """
        %PDF-1.4
        1 0 obj
        << /Type /Catalog /Pages 2 0 R >>
        endobj
        2 0 obj
        << /Type /Pages /Kids [3 0 R] /Count 1 >>
        endobj
        3 0 obj
        << /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] /Contents 4 0 R /Resources << /Font << /F1 5 0 R >> >> >>
        endobj
        4 0 obj
        << /Length 100 >>
        stream
        BT
        /F1 24 Tf
        100 700 Td
        (\(title)) Tj
        ET
        endstream
        endobj
        5 0 obj
        << /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>
        endobj
        xref
        0 6
        0000000000 65535 f 
        0000000009 00000 n 
        0000000058 00000 n 
        0000000115 00000 n 
        0000000266 00000 n 
        0000000416 00000 n 
        trailer
        << /Size 6 /Root 1 0 R >>
        startxref
        494
        %%EOF
        """
        try content.write(to: url, atomically: true, encoding: .utf8)
    }
    
    private func generateText(name: String, category: String, at url: URL) throws {
        let title = name.replacingOccurrences(of: "_", with: " ")
        let content = """
        \(title)
        ================
        Category: \(category)
        Generated: \(Date())
        
        This is a test document for SortAI categorization testing.
        
        The file contains sample content that represents a typical
        document in the \(category) category.
        
        Keywords: \(category.components(separatedBy: "/").joined(separator: ", "))
        """
        try content.write(to: url, atomically: true, encoding: .utf8)
    }
    
    private func generateDocx(name: String, at url: URL) throws {
        // Minimal DOCX is a ZIP with XML files
        // For simplicity, create a text file with .docx extension and DOCX magic bytes
        var data = Data([0x50, 0x4B, 0x03, 0x04])  // ZIP signature
        // Add minimal content
        let title = name.replacingOccurrences(of: "_", with: " ")
        data.append(title.data(using: .utf8) ?? Data())
        data.append(Data(repeating: 0, count: 1000))  // Padding
        try data.write(to: url)
    }
    
    // MARK: - Image Generators
    
    private func generateJPEG(name: String, at url: URL) throws {
        // Create a minimal valid JPEG
        // JPEG starts with FFD8 and ends with FFD9
        var data = Data([0xFF, 0xD8, 0xFF, 0xE0, 0x00, 0x10, 0x4A, 0x46, 0x49, 0x46, 0x00])  // JFIF marker
        // Add APP0 segment, quantization tables, huffman tables, etc. (minimal)
        // SOF0 (Start Of Frame)
        data.append(contentsOf: [0xFF, 0xC0, 0x00, 0x0B, 0x08, 0x00, 0x10, 0x00, 0x10, 0x01, 0x01, 0x11, 0x00])
        // DHT (Huffman table)
        data.append(contentsOf: [0xFF, 0xC4, 0x00, 0x14, 0x00, 0x01, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00])
        // SOS (Start Of Scan)
        data.append(contentsOf: [0xFF, 0xDA, 0x00, 0x08, 0x01, 0x01, 0x00, 0x00, 0x3F, 0x00])
        // Some scan data
        data.append(Data(repeating: 0x7F, count: 100))
        // EOI (End Of Image)
        data.append(contentsOf: [0xFF, 0xD9])
        try data.write(to: url)
    }
    
    private func generatePNG(name: String, at url: URL) throws {
        // Create a minimal valid PNG (1x1 white pixel)
        let pngData = Data([
            0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A,  // PNG signature
            0x00, 0x00, 0x00, 0x0D,  // IHDR length
            0x49, 0x48, 0x44, 0x52,  // IHDR
            0x00, 0x00, 0x00, 0x10,  // width: 16
            0x00, 0x00, 0x00, 0x10,  // height: 16
            0x08, 0x02,              // bit depth: 8, color type: RGB
            0x00, 0x00, 0x00,        // compression, filter, interlace
            0x90, 0x77, 0x53, 0xDE,  // CRC
            0x00, 0x00, 0x00, 0x0C,  // IDAT length
            0x49, 0x44, 0x41, 0x54,  // IDAT
            0x08, 0xD7, 0x63, 0xF8, 0xFF, 0xFF, 0xFF, 0x00, 0x05, 0xFE, 0x02, 0xFE,  // compressed data
            0xA4, 0x28, 0xC6, 0x3A,  // CRC
            0x00, 0x00, 0x00, 0x00,  // IEND length
            0x49, 0x45, 0x4E, 0x44,  // IEND
            0xAE, 0x42, 0x60, 0x82   // CRC
        ])
        try pngData.write(to: url)
    }
    
    // MARK: - Video Generators
    
    private func generateMP4(name: String, at url: URL) throws {
        // Create a minimal valid MP4 (ftyp + moov atoms)
        var data = Data()
        
        // ftyp atom
        let ftyp: [UInt8] = [
            0x00, 0x00, 0x00, 0x18,  // size: 24
            0x66, 0x74, 0x79, 0x70,  // type: ftyp
            0x69, 0x73, 0x6F, 0x6D,  // major brand: isom
            0x00, 0x00, 0x02, 0x00,  // minor version
            0x69, 0x73, 0x6F, 0x6D,  // compatible brand: isom
            0x69, 0x73, 0x6F, 0x32   // compatible brand: iso2
        ]
        data.append(contentsOf: ftyp)
        
        // moov atom (minimal)
        let moov: [UInt8] = [
            0x00, 0x00, 0x00, 0x08,  // size: 8
            0x6D, 0x6F, 0x6F, 0x76   // type: moov
        ]
        data.append(contentsOf: moov)
        
        // Add some padding for realistic file size
        data.append(Data(repeating: 0, count: 10000))
        
        try data.write(to: url)
    }
    
    private func generateMOV(name: String, at url: URL) throws {
        // MOV is similar to MP4, uses qt brand
        var data = Data()
        
        // ftyp atom
        let ftyp: [UInt8] = [
            0x00, 0x00, 0x00, 0x14,  // size: 20
            0x66, 0x74, 0x79, 0x70,  // type: ftyp
            0x71, 0x74, 0x20, 0x20,  // major brand: qt
            0x00, 0x00, 0x02, 0x00,  // minor version
            0x71, 0x74, 0x20, 0x20   // compatible brand: qt
        ]
        data.append(contentsOf: ftyp)
        
        // moov atom (minimal)
        let moov: [UInt8] = [
            0x00, 0x00, 0x00, 0x08,
            0x6D, 0x6F, 0x6F, 0x76
        ]
        data.append(contentsOf: moov)
        
        data.append(Data(repeating: 0, count: 8000))
        
        try data.write(to: url)
    }
    
    // MARK: - Audio Generators
    
    private func generateMP3(name: String, at url: URL) throws {
        // Create a minimal valid MP3 with ID3 tag
        var data = Data()
        
        // ID3v2 header
        let id3: [UInt8] = [
            0x49, 0x44, 0x33,        // ID3
            0x04, 0x00,              // version 2.4.0
            0x00,                    // flags
            0x00, 0x00, 0x00, 0x00   // size (0)
        ]
        data.append(contentsOf: id3)
        
        // MP3 frame header (128kbps, 44.1kHz, stereo)
        let frameHeader: [UInt8] = [
            0xFF, 0xFB, 0x90, 0x00
        ]
        
        // Add several frames for realistic size
        for _ in 0..<100 {
            data.append(contentsOf: frameHeader)
            data.append(Data(repeating: 0x00, count: 417))  // Frame data
        }
        
        try data.write(to: url)
    }
    
    private func generateM4A(name: String, at url: URL) throws {
        // M4A is essentially MP4 audio
        var data = Data()
        
        // ftyp atom
        let ftyp: [UInt8] = [
            0x00, 0x00, 0x00, 0x18,
            0x66, 0x74, 0x79, 0x70,
            0x4D, 0x34, 0x41, 0x20,  // major brand: M4A
            0x00, 0x00, 0x02, 0x00,
            0x4D, 0x34, 0x41, 0x20,
            0x6D, 0x70, 0x34, 0x32   // compatible brand: mp42
        ]
        data.append(contentsOf: ftyp)
        
        // moov atom
        let moov: [UInt8] = [
            0x00, 0x00, 0x00, 0x08,
            0x6D, 0x6F, 0x6F, 0x76
        ]
        data.append(contentsOf: moov)
        
        data.append(Data(repeating: 0, count: 5000))
        
        try data.write(to: url)
    }
    
    // MARK: - Code Generators
    
    private func generateCode(name: String, type: TestFile.FileType, at url: URL) throws {
        let content: String
        switch type {
        case .swift:
            content = """
            // \(name)
            // Generated for SortAI testing
            
            import Foundation
            
            struct \(name.replacingOccurrences(of: ".swift", with: "").replacingOccurrences(of: "_", with: "")) {
                let id: UUID
                let name: String
                let createdAt: Date
                
                func process() async throws {
                    // Implementation
                }
            }
            """
        case .python:
            content = """
            # \(name)
            # Generated for SortAI testing
            
            import os
            from datetime import datetime
            
            class \(name.replacingOccurrences(of: ".py", with: "").replacingOccurrences(of: "_", with: "")):
                def __init__(self, name: str):
                    self.name = name
                    self.created_at = datetime.now()
                
                def process(self):
                    pass
            """
        case .javascript:
            content = """
            // \(name)
            // Generated for SortAI testing
            
            module.exports = {
                name: '\(name)',
                version: '1.0.0',
                
                process: async function() {
                    // Implementation
                }
            };
            """
        case .typescript:
            content = """
            // \(name)
            // Generated for SortAI testing
            
            import React from 'react';
            
            interface Props {
                name: string;
            }
            
            export const Component: React.FC<Props> = ({ name }) => {
                return <div>{name}</div>;
            };
            """
        default:
            content = "// \(name)"
        }
        try content.write(to: url, atomically: true, encoding: .utf8)
    }
    
    private func generateJupyter(name: String, at url: URL) throws {
        let content = """
        {
         "cells": [
          {
           "cell_type": "markdown",
           "metadata": {},
           "source": ["# \(name.replacingOccurrences(of: ".ipynb", with: ""))\\n", "Generated for SortAI testing"]
          },
          {
           "cell_type": "code",
           "execution_count": null,
           "metadata": {},
           "outputs": [],
           "source": ["import pandas as pd\\n", "import numpy as np\\n", "\\n", "# Analysis code here"]
          }
         ],
         "metadata": {
          "kernelspec": {
           "display_name": "Python 3",
           "language": "python",
           "name": "python3"
          }
         },
         "nbformat": 4,
         "nbformat_minor": 4
        }
        """
        try content.write(to: url, atomically: true, encoding: .utf8)
    }
    
    // MARK: - Data File Generators
    
    private func generateCSV(name: String, at url: URL) throws {
        let content = """
        id,name,value,date,category
        1,Item A,100.50,2025-01-01,CategoryA
        2,Item B,200.75,2025-01-02,CategoryB
        3,Item C,150.25,2025-01-03,CategoryA
        4,Item D,300.00,2025-01-04,CategoryC
        5,Item E,175.50,2025-01-05,CategoryB
        """
        try content.write(to: url, atomically: true, encoding: .utf8)
    }
    
    private func generateXLSX(name: String, at url: URL) throws {
        // XLSX is a ZIP file with XML content
        var data = Data([0x50, 0x4B, 0x03, 0x04])  // ZIP signature
        let title = name.replacingOccurrences(of: "_", with: " ")
        data.append(title.data(using: .utf8) ?? Data())
        data.append(Data(repeating: 0, count: 2000))
        try data.write(to: url)
    }
    
    private func generateJSON(name: String, at url: URL) throws {
        let content = """
        {
            "name": "\(name)",
            "generated": "\(Date())",
            "data": {
                "items": [
                    {"id": 1, "value": "test1"},
                    {"id": 2, "value": "test2"},
                    {"id": 3, "value": "test3"}
                ],
                "metadata": {
                    "version": "1.0",
                    "format": "json"
                }
            }
        }
        """
        try content.write(to: url, atomically: true, encoding: .utf8)
    }
    
    private func generateYAML(name: String, at url: URL) throws {
        let content = """
        # \(name)
        # Generated for SortAI testing
        
        name: \(name)
        version: 1.0.0
        
        settings:
          debug: false
          timeout: 30
          max_connections: 100
        
        database:
          host: localhost
          port: 5432
          name: production
        """
        try content.write(to: url, atomically: true, encoding: .utf8)
    }
    
    private func generateSQLite(name: String, at url: URL) throws {
        // SQLite file header
        var data = Data("SQLite format 3\0".utf8)
        data.append(Data(repeating: 0, count: 100 - data.count))  // Page size, etc.
        data.append(Data(repeating: 0, count: 4096 - data.count))  // First page
        try data.write(to: url)
    }
    
    // MARK: - Archive Generators
    
    private func generateZIP(name: String, at url: URL) throws {
        // Minimal ZIP file
        var data = Data()
        
        // Local file header
        let localHeader: [UInt8] = [
            0x50, 0x4B, 0x03, 0x04,  // signature
            0x0A, 0x00,              // version needed
            0x00, 0x00,              // flags
            0x00, 0x00,              // compression
            0x00, 0x00,              // mod time
            0x00, 0x00,              // mod date
            0x00, 0x00, 0x00, 0x00,  // crc32
            0x00, 0x00, 0x00, 0x00,  // compressed size
            0x00, 0x00, 0x00, 0x00,  // uncompressed size
            0x08, 0x00,              // filename length
            0x00, 0x00               // extra field length
        ]
        data.append(contentsOf: localHeader)
        data.append("test.txt".data(using: .utf8)!)
        
        // Central directory
        let centralDir: [UInt8] = [
            0x50, 0x4B, 0x01, 0x02,  // signature
            0x0A, 0x00,              // version made by
            0x0A, 0x00,              // version needed
            0x00, 0x00,              // flags
            0x00, 0x00,              // compression
            0x00, 0x00, 0x00, 0x00,  // mod time/date
            0x00, 0x00, 0x00, 0x00,  // crc32
            0x00, 0x00, 0x00, 0x00,  // compressed size
            0x00, 0x00, 0x00, 0x00,  // uncompressed size
            0x08, 0x00,              // filename length
            0x00, 0x00,              // extra field length
            0x00, 0x00,              // comment length
            0x00, 0x00,              // disk number
            0x00, 0x00,              // internal attrs
            0x00, 0x00, 0x00, 0x00,  // external attrs
            0x00, 0x00, 0x00, 0x00   // offset
        ]
        data.append(contentsOf: centralDir)
        data.append("test.txt".data(using: .utf8)!)
        
        // End of central directory
        let endCentralDir: [UInt8] = [
            0x50, 0x4B, 0x05, 0x06,  // signature
            0x00, 0x00,              // disk number
            0x00, 0x00,              // disk with cd
            0x01, 0x00,              // entries on disk
            0x01, 0x00,              // total entries
            0x36, 0x00, 0x00, 0x00,  // cd size
            0x26, 0x00, 0x00, 0x00,  // cd offset
            0x00, 0x00               // comment length
        ]
        data.append(contentsOf: endCentralDir)
        
        try data.write(to: url)
    }
    
    private func generateTarGz(name: String, at url: URL) throws {
        // Gzip header + minimal tar content
        var data = Data()
        
        // Gzip header
        let gzipHeader: [UInt8] = [
            0x1F, 0x8B,  // magic
            0x08,        // deflate
            0x00,        // flags
            0x00, 0x00, 0x00, 0x00,  // mtime
            0x00,        // extra flags
            0xFF         // OS (unknown)
        ]
        data.append(contentsOf: gzipHeader)
        
        // Minimal compressed content
        data.append(Data(repeating: 0, count: 512))
        
        // Gzip trailer
        data.append(Data(repeating: 0, count: 8))
        
        try data.write(to: url)
    }
    
    private func generateEPUB(name: String, at url: URL) throws {
        // EPUB is a ZIP file with specific structure
        // For simplicity, create a ZIP with mimetype
        try generateZIP(name: name, at: url)
    }
    
    // MARK: - Category Mapping
    
    private func createCategoryMapping() throws {
        var mapping: [String: String] = [:]
        
        for (_, files) in categories {
            for file in files {
                mapping[file.name] = file.category
            }
        }
        
        let data = try JSONSerialization.data(withJSONObject: mapping, options: [.prettyPrinted, .sortedKeys])
        let url = baseDir.appendingPathComponent("category_mapping.json")
        try data.write(to: url)
        
        print("📋 Created category mapping: category_mapping.json")
    }
}

// MARK: - Main

do {
    let generator = TestDataGenerator(outputDir: outputDir)
    try generator.generate()
} catch {
    print("❌ Error: \(error.localizedDescription)")
    exit(1)
}


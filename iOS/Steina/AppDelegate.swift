//
//  AppDelegate.swift
//  Steina
//
//  Created by Sean Hickey on 5/9/18.
//  Copyright © 2018 Massachusetts Institute of Technology. All rights reserved.
//

import UIKit

let ImportedProjectNotification = Notification(name: Notification.Name(rawValue: "BricoleurImportedProject"))

@UIApplicationMain
class AppDelegate: UIResponder, UIApplicationDelegate {

    var window: UIWindow?

    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplicationLaunchOptionsKey: Any]?) -> Bool {
        cleanUpAirdropInbox()
        
        // Preload project manifest and thumbnails
        SteinaStore.loadProjectsManifest()
        for untypedProject in SteinaStore.projects {
            let project = untypedProject as! Project
            loadProjectThumbnail(project)
        }
        
        // Audio
        initAudioSystem()
        startAudio()
        
        return true
    }
    
    func application(_ app: UIApplication, open url: URL, options: [UIApplicationOpenURLOptionsKey : Any] = [:]) -> Bool {
        // We recreate the temp folder for every incoming file so that unzipping always produces a single uniquely named directory
        let tempFolder = DATA_DIRECTORY_URL.appendingPathComponent("temp")
        try! FileManager.default.createDirectory(at: tempFolder, withIntermediateDirectories: true, attributes: nil)
        
        let success = SSZipArchive.unzipFile(atPath: url.path, toDestination: tempFolder.path)
        if success {
            let projectFolderName = (try! FileManager.default.contentsOfDirectory(atPath: tempFolder.path))[0]
            let projectFolderUrl = tempFolder.appendingPathComponent(projectFolderName)
            let newProjectId = UUID()
            let newProjectFolder = DATA_DIRECTORY_URL.appendingPathComponent(newProjectId.uuidString, isDirectory: true)
            try! FileManager.default.moveItem(at: projectFolderUrl, to: newProjectFolder)
            
            let project = Project(id: newProjectId)
            SteinaStore.projects.add(project)
            SteinaStore.saveProjectsManifest()
            loadProjectThumbnail(project)
            
            NotificationCenter.default.post(ImportedProjectNotification)
        }
        
        try! FileManager.default.removeItem(at: tempFolder)
        return success
    }
    
    func cleanUpAirdropInbox() {
        let inboxUrl = DATA_DIRECTORY_URL.appendingPathComponent("Inbox")
        if FileManager.default.fileExists(atPath: inboxUrl.path) {
            let items = try! FileManager.default.contentsOfDirectory(atPath: inboxUrl.path)
            for item in items {
                let itemUrl = inboxUrl.appendingPathComponent(item)
                try! FileManager.default.removeItem(at: itemUrl)
            }
        }
    }

    func applicationWillResignActive(_ application: UIApplication) {
        // Sent when the application is about to move from active to inactive state. This can occur for certain types of temporary interruptions (such as an incoming phone call or SMS message) or when the user quits the application and it begins the transition to the background state.
        // Use this method to pause ongoing tasks, disable timers, and invalidate graphics rendering callbacks. Games should use this method to pause the game.
    }

    func applicationDidEnterBackground(_ application: UIApplication) {
        // Use this method to release shared resources, save user data, invalidate timers, and store enough application state information to restore your application to its current state in case it is terminated later.
        // If your application supports background execution, this method is called instead of applicationWillTerminate: when the user quits.
    }

    func applicationWillEnterForeground(_ application: UIApplication) {
        // Called as part of the transition from the background to the active state; here you can undo many of the changes made on entering the background.
    }

    func applicationDidBecomeActive(_ application: UIApplication) {
        // Restart any tasks that were paused (or not yet started) while the application was inactive. If the application was previously in the background, optionally refresh the user interface.
    }

    func applicationWillTerminate(_ application: UIApplication) {
        // Called when the application is about to terminate. Save data if appropriate. See also applicationDidEnterBackground:.
        // Saves changes in the application's managed object context before the application terminates.
    }

}


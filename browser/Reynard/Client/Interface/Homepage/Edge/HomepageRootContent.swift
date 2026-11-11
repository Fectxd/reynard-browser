//
//  HomepageRootContent.swift
//  Reynard
//
//  Common surface shared by upstream's HomepageRootViewController (used for the
//  small homepage that appears while the address bar is focused) and the Edge
//  start page (used for homepage tabs), so HomepageViewController can host
//  either one.
//

import UIKit

enum HomepageStyle {
    /// Upstream Reynard homepage. Used by the address-bar focus overlay.
    case classic
    /// Paged Edge-style start page. Used by homepage / new tabs.
    case edge
}

protocol HomepageRootContent: UIViewController {
    func setContentMode(_ contentMode: HomepageContentMode)
    func setPrivateBrowsing(_ isPrivateBrowsing: Bool)
    func setVisibleContentInsets(_ visibleContentInsets: UIEdgeInsets)
}

extension HomepageRootViewController: HomepageRootContent {}

protocol HomepageViewControllerAddressBarDelegate: AnyObject {
    func homepageViewControllerDidRequestAddressBarFocus(_ controller: HomepageViewController)
}

extension HomepageViewController: EdgeStartPageViewControllerDelegate {
    func edgeStartPage(_ controller: EdgeStartPageViewController, didRequestOpenURL url: URL, disposition: TabOpenDisposition) {
        homepageDelegate?.homepageViewController(self, didRequestOpenURL: url, disposition: disposition)
    }
    
    func edgeStartPage(_ controller: EdgeStartPageViewController, didRequestShareURL url: URL, sourceView: UIView) {
        homepageDelegate?.homepageViewController(self, didRequestShareURL: url, sourceView: sourceView)
    }
    
    func edgeStartPage(_ controller: EdgeStartPageViewController, didRequestHideFromSuggestions siteID: Int64) {
        homepageDelegate?.homepageViewController(self, didRequestHideFromSuggestions: siteID)
    }
    
    func edgeStartPage(_ controller: EdgeStartPageViewController, didSelectRecentlyClosedTab id: UUID) {
        homepageDelegate?.homepageViewController(self, didSelectRecentlyClosedTab: id)
    }
    
    func edgeStartPageDidSelectFolder(_ folder: BookmarkFolderSnapshot) {
        homepageRootViewControllerDidSelectFolder(folder)
    }
    
    func edgeStartPageDidRequestAddressBarFocus(_ controller: EdgeStartPageViewController) {
        addressBarDelegate?.homepageViewControllerDidRequestAddressBarFocus(self)
    }
    
    func edgeStartPageDidStartScrolling() {
        homepageDelegate?.homepageViewControllerDidStartScrolling()
    }
}

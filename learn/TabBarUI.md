```swift
// TabBarControllerImpl
override open func loadDisplayNode() {
    self.displayNode = TabBarControllerNode(theme: self.theme, navigationBarPresentationData: self.navigationBarPresentationData, itemSelected: { [weak self]

// TabBarControllerNode
init
    self.tabBarNode = TabBarNode(theme: theme, itemSelected: itemSelected, contextAction: contextAction, swipeAction: swipeAction)

// TabBarNode











```
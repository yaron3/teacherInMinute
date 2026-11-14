import Testing
@testable import TeacherMinute

/// IT-34: a package saved twice in the `pricing` collection is offered once.
struct PricingPackageDedupeTests {

    private func option(
        id: String,
        name: String = "1-Minute",
        minutes: Int? = 1,
        priceCents: Int = 100,
        currency: String = "ILS",
        sortOrder: Int = 0
    ) -> PricingOption {
        PricingOption(
            id: id,
            name: name,
            priceCents: priceCents,
            currency: currency,
            type: .payAsYouGo,
            description: "",
            isHighlighted: false,
            sortOrder: sortOrder,
            purchaseSKU: nil,
            minutesGranted: minutes
        )
    }

    @Test func aPackageSavedTwiceIsOfferedOnce() {
        let result = PricingService.uniquePackages([
            option(id: "random-a", sortOrder: 1),
            option(id: "random-b", sortOrder: 2),
        ])

        #expect(result.map(\.id) == ["random-a"])
    }

    @Test func theFirstInSortOrderIsKept() {
        let result = PricingService.uniquePackages([
            option(id: "late", sortOrder: 5),
            option(id: "early", sortOrder: 1),
        ].sorted { $0.sortOrder < $1.sortOrder })

        #expect(result.map(\.id) == ["early"])
    }

    @Test func packagesThatDifferInAnyFieldAreBothKept() {
        let result = PricingService.uniquePackages([
            option(id: "a"),
            option(id: "b", name: "5-Minute", minutes: 5),
            option(id: "c", priceCents: 250),
            option(id: "d", currency: "USD"),
        ])

        #expect(result.map(\.id) == ["a", "b", "c", "d"])
    }
}

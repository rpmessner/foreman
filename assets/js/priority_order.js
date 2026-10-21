// Reorder existing cards instead of remounting forms when board priority changes.
export const PriorityOrder = {
  mounted() { this.reorder() },
  beforeUpdate() {
    this.drafts = [...this.el.querySelectorAll('input, textarea, select')]
      .map(el => ({el, value: el.value, checked: el.checked}))
  },
  updated() {
    // LiveView patches unfocused controls from their original server values.
    for (const {el, value, checked} of this.drafts || []) {
      if (this.el.contains(el)) {
        el.value = value
        if (typeof checked === 'boolean') el.checked = checked
      }
    }
    this.drafts = []
    this.reorder()
  },
  reorder() {
    const cards = [...this.el.children].filter(el => el.hasAttribute("data-priority-order"))
    cards.sort((a, b) => Number(a.dataset.priorityOrder) - Number(b.dataset.priorityOrder))
    cards.forEach((card, index) => {
      const current = [...this.el.children].filter(el => el.hasAttribute("data-priority-order"))[index]
      if (current !== card) this.el.insertBefore(card, current)
    })
  }
}

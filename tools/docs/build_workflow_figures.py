"""Generate workflow flowcharts with the existing SVG teaching primitives."""
from build_teaching_figures import SVG, BLUE, TEAL, ORANGE


def decision(svg, x, y, width, height, lines):
    middle_x = x + width / 2
    middle_y = y + height / 2
    svg.s.append(
        f'<polygon points="{middle_x},{y} {x+width},{middle_y} '
        f'{middle_x},{y+height} {x},{middle_y}" '
        f'fill="#f5f9fc" stroke="{TEAL}" stroke-width="2"/>'
    )
    for index, label in enumerate(lines):
        svg.text(middle_x, middle_y - 7 + 24 * index, label, 17, TEAL)


def input_workflow():
    svg = SVG('Parse, validate, prepare and hand off a network', h=1040)
    svg.box(40, 70, 490, 85, ['Parse source and preserve supplied state', 'RAW / MATPOWER / explicit Case'])
    svg.line(285, 155, 285, 185, arrow=True)
    svg.box(40, 185, 490, 110, ['Check identities, units and model coverage', 'Replay saved VM / VA / PG / QG when present', 'Record missing ratings and explicit assumptions'])
    svg.line(285, 295, 285, 325, arrow=True)
    decision(svg, 60, 325, 450, 100, ['Inputs supported and', 'study assumptions complete?'])
    svg.line(510, 375, 615, 375, arrow=True)
    svg.text(558, 355, 'No', 16, ORANGE)
    svg.box(625, 325, 340, 110, ['Review source or declarations', 'Retain the supplied snapshot', 'Resolve coverage explicitly'], ORANGE)
    svg.line(285, 425, 285, 470, arrow=True)
    svg.text(314, 452, 'Yes', 16, TEAL)
    svg.box(40, 470, 490, 110, ['Declare the target problem', 'Objective, control bounds and equipment policy', 'Training states and frozen evaluation settings'])
    svg.line(285, 580, 285, 615, arrow=True)
    svg.box(40, 615, 490, 110, ['Prepare numerical starts', 'Use qualified same-contract / nearby states', 'Or declare a fixed-control preparatory solve'])
    svg.line(285, 725, 285, 760, arrow=True)
    svg.box(40, 760, 490, 110, ['Hand off to the target design model', 'Map identities and transfer complete primals', 'Check target settings, residuals and seed origin'])
    svg.line(285, 870, 285, 905, arrow=True)
    svg.box(40, 905, 490, 80, ['Run the selected design workflow', 'Retain its own objectives and acceptance gates'], TEAL)
    svg.box(625, 630, 340, 110, ['Source data and numerical hints', 'have separate provenance', 'Physical limits stay explicit'], TEAL)
    svg.text(500, 1020, 'Input checking and declared conversion precede any optimization.', 17)
    svg.save('input_design_workflow')


def staged_workflow():
    svg = SVG('Local staged design objectives and handoff gates', h=1030)
    stages = [
        (75, ['Feasibility', 'Minimize zero under the declared constraints']),
        (255, ['Reserve initialization', 'Maximize common symmetric Q-box fraction']),
        (435, ['Design feasibility', 'Minimize zero with the retained reserve floor']),
        (615, ['Loss design', 'Minimize active losses under the retained floor']),
    ]
    for index, (y, lines) in enumerate(stages):
        svg.box(40, y, 550, 95, lines)
        if index < len(stages) - 1:
            svg.line(315, y + 95, 315, y + 175, arrow=True)
            svg.text(340, y + 125, 'Convergence + replay', 16, TEAL, anchor='start')
            svg.text(340, y + 150, 'Transfer all accepted primals', 15, anchor='start')
        svg.line(590, y + 47, 660, y + 47, arrow=True)
        svg.text(625, y + 32, 'Fail', 15, ORANGE)
    svg.line(660, 122, 660, 662, color=ORANGE)
    svg.box(685, 280, 280, 110, ['Stop the sequence', 'Retain failure diagnostics', 'Review model or retry seed'], ORANGE)
    svg.line(660, 335, 685, 335, color=ORANGE, arrow=True)
    svg.box(685, 455, 280, 110, ['Native and prepared APIs', 'have distinct control and', 'numerical contracts'], TEAL)
    svg.line(315, 710, 315, 750, arrow=True)
    decision(svg, 75, 750, 480, 105, ['All four stages accepted', 'and final sequence replayed?'])
    svg.line(315, 855, 315, 900, arrow=True)
    svg.text(345, 882, 'Yes', 16, TEAL)
    svg.box(40, 900, 550, 80, ['Review losses, reserve and control movement', 'Then evaluate the frozen design'], TEAL)
    svg.line(555, 802, 660, 802, color=ORANGE, arrow=True)
    svg.text(606, 784, 'No', 15, ORANGE)
    svg.line(660, 802, 660, 662, color=ORANGE)
    svg.text(500, 1010, 'Reserve floor = max(0, accepted initialized fraction - 1e-8).', 17)
    svg.save('staged_design_workflow')


def review_workflow():
    svg = SVG('Review qualified candidates and choose a design', h=1060)
    decision(svg, 45, 80, 500, 105, ['Native solver convergence', 'and independent replay pass?'])
    svg.line(545, 132, 625, 132, arrow=True)
    svg.text(585, 113, 'No', 16, ORANGE)
    svg.box(640, 75, 320, 115, ['Retain unresolved / failed result', 'Inspect coverage and residuals', 'Retry a qualified mapped start'], ORANGE)
    svg.line(295, 185, 295, 230, arrow=True)
    svg.text(325, 212, 'Yes', 16, TEAL)
    svg.box(45, 230, 500, 110, ['Compare matched candidates', 'Same source, limits, controls and state coverage', 'Same objective and numerical budgets'])
    svg.line(295, 340, 295, 375, arrow=True)
    svg.box(45, 375, 500, 110, ['Review physical and numerical performance', 'Losses, reserve, voltage and thermal margins', 'Iterations, runtime, memory and retries'])
    svg.line(295, 485, 295, 525, arrow=True)
    decision(svg, 45, 525, 500, 105, ['Meets declared requirements', 'and objective priorities?'])
    svg.line(545, 577, 625, 577, arrow=True)
    svg.text(585, 559, 'No', 16, ORANGE)
    svg.box(640, 520, 320, 115, ['Revisit declared choices', 'Try a matched solver or start', 'Record every changed assumption'], ORANGE)
    svg.line(295, 630, 295, 675, arrow=True)
    svg.text(325, 656, 'Yes', 16, TEAL)
    svg.box(45, 675, 500, 110, ['Freeze the selected controller and settings', 'Replay held-out demands and schedule interiors', 'Check declared outages / periods when required'])
    svg.line(295, 785, 295, 825, arrow=True)
    decision(svg, 45, 825, 500, 105, ['Required evaluation coverage', 'passes original-limit replay?'])
    svg.line(545, 877, 625, 877, arrow=True)
    svg.text(585, 859, 'No', 16, ORANGE)
    svg.box(640, 830, 320, 110, ['Retain the coverage gap', 'Add training states if authorized', 'Re-evaluate the common design'], ORANGE)
    svg.line(295, 930, 295, 965, arrow=True)
    svg.box(45, 965, 500, 65, ['Select and report the verified design scope'], TEAL)
    svg.save('design_review_workflow')


if __name__ == '__main__':
    input_workflow()
    staged_workflow()
    review_workflow()
    print('Generated three workflow teaching flowcharts')

import os
import sys
from math import pi
from data_handler import Modeller, SaveData, Optimizer, Material, CompliancePNorm, ComplianceSmoothTheta, ComplianceMu, ComplianceNominal
import numpy as np

# ================================ Defining case ================================

#filename = files[0]
#filename = sys.argv[1]

def run(filename):
    optimize = True
    # ================================ Create json file ================================
    if optimize:
        save_data = SaveData(step=1,
                                save_angles=False,
                                save_areas=False,
                                save_forces=False,
                                save_compliance=True,
                                save_move=False,
                                save_volume=False,
                                save_error=False)
        
        #comp = ComplianceMu(0.1)
        comp = ComplianceSmoothTheta(theta_r=np.radians(1), beta=0.01)
        #comp = CompliancePNorm(p=20.0)
        #comp = ComplianceNominal()

        optimizer_data = Optimizer(compliance=comp,
                                    volume_max=1.0,
                                    min_iterations=2,
                                    max_iterations=5000,
                                    use_adaptive_move=False,
                                    initial_move_multiplier=0.1,
                                    use_adaptive_damping=False,
                                    initial_damping=0.0,
                                    use_layout_constraint=False,
                                    x_min=1e-12,
                                    tolerance=1e-8)

        modeller = Modeller(filename=filename,
                            data_to_save=save_data,
                            optimizer=optimizer_data)

        material = Material(1, 1.0)

        modeller.read_structure_from_dxf(elements_material=material, elements_area=1e-5)

        # modeller.write_dxf()
        modeller.write_json()

        # ================================ Run Julia optimization ================================
        os.system(f'julia main.jl {modeller.filename}')

    # ================================ Read optimized structure ================================
    markers_sizes = 0.05
    markers_width = 2

    modeller = Modeller.read(f'{filename}')

    modeller.plot_initial_structure(default_width=0.5,
                                    lc_width=3,
                                    supports_markers_size=markers_sizes,
                                    supports_markers_width=markers_width,
                                    supports_markers_color='green',
                                    forces_markers_size=1,                                  
                                    forces_markers_color='gray',
                                    plot_loads=True,
                                    plot_supports=True)

    modeller.plot_optimized_structure(cutoff=1e-4,
                                    base_width=1,
                                    supports_markers_size=markers_sizes,
                                    supports_markers_width=markers_width,
                                    supports_markers_color='green',
                                    forces_markers_size=1,
                                    forces_markers_color='gray',
                                    plot_loads=False,
                                    plot_supports=True)

    modeller.plot_compliance()

run('fan_circle.json')

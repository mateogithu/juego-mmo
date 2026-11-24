Carpeta de Modelos 3D Personalizados (.glb / glTF 2.0)
=====================================================

Crónicas del Orden y el Caos soporta reemplazo automático de modelos 3D sin modificar código.
Si colocás archivos .glb en esta carpeta (res://Assets/Models/) con los siguientes nombres exactos,
ProceduralMeshFactory.gd los cargará automáticamente reemplazando los modelos esculpidos procedurales:

- player_knight.glb   -> Caballero Arcano
- player_mage.glb     -> Piromante / Hechicero
- player_cleric.glb   -> Clérigo de Guerra
- player_rogue.glb    -> Asesino Sombrío
- dragon.glb          -> Montura Dragón

Convención recomendada:
- Frente del personaje mirando hacia +Z (estándar glTF/Mixamo/Blender; el motor lo orienta automáticamente).
- Altura humana aproximada: 1.80 m con pies en Y = 0.

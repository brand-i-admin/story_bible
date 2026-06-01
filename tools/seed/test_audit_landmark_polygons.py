"""Unit tests for tools/seed/audit_landmark_polygons.py."""

from __future__ import annotations

import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

import audit_landmark_polygons as mod  # noqa: E402


class AuditLandmarkPolygonsTests(unittest.TestCase):
    def test_axis_aligned_edge_count_detects_rectangle(self) -> None:
        polygon = [[0.0, 0.0], [0.0, 1.0], [1.0, 1.0], [1.0, 0.0]]

        self.assertEqual(mod.axis_aligned_edge_count(polygon), 4)

    def test_audit_regions_flags_boxy_or_low_vertex_polygons(self) -> None:
        catalog = {
            "regions": [
                {
                    "code": "rgn_box",
                    "name": "상자",
                    "polygon": [[0.0, 0.0], [0.0, 1.0], [1.0, 1.0], [1.0, 0.0]],
                },
                {
                    "code": "rgn_smooth",
                    "name": "곡선",
                    "polygon": [
                        [0.00, 0.00],
                        [0.08, 0.17],
                        [0.21, 0.29],
                        [0.35, 0.35],
                        [0.49, 0.31],
                        [0.61, 0.19],
                        [0.70, 0.02],
                        [0.68, -0.16],
                        [0.57, -0.31],
                        [0.40, -0.39],
                        [0.21, -0.37],
                        [0.04, -0.27],
                        [-0.08, -0.10],
                        [-0.10, 0.07],
                        [-0.04, 0.18],
                        [0.00, 0.00],
                        [0.03, 0.06],
                        [0.09, 0.11],
                        [0.16, 0.13],
                        [0.24, 0.10],
                        [0.30, 0.04],
                    ],
                },
            ]
        }

        findings = mod.audit_regions(catalog, max_vertices=20, min_axis_ratio=0.55)

        self.assertEqual([item["code"] for item in findings], ["rgn_box"])
        self.assertEqual(findings[0]["vertex_count"], 4)
        self.assertEqual(findings[0]["axis_aligned_edges"], 4)


if __name__ == "__main__":
    unittest.main()

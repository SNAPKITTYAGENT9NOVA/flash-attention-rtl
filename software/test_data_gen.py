"""
FlashAttention RTL - Test Data Generation & Utilities
Generates reference test vectors for hardware simulation
"""

import numpy as np
from pathlib import Path
import json


class TestDataGenerator:
    """
    Generate realistic test data with known properties for RTL verification.
    Supports multiple data types and numeric ranges.
    """
    
    def __init__(self, seed: int = 42, dtype: np.dtype = np.float32):
        self.seed = seed
        self.dtype = dtype
        np.random.seed(seed)
    
    def generate_attention_inputs(
        self,
        seq_len: int,
        d_model: int,
        scale: float = None,
        low: float = -1.0,
        high: float = 1.0
    ) -> dict:
        """
        Generate Q, K, V inputs for attention computation.
        
        Args:
            seq_len: Sequence length N
            d_model: Embedding dimension
            scale: Optional scaling factor (default: 1/sqrt(d_model))
            low, high: Range for random values
            
        Returns:
            dict with Q, K, V arrays
        """
        if scale is None:
            scale = 1.0 / np.sqrt(d_model)
        
        Q = np.random.uniform(low, high, (seq_len, d_model)).astype(self.dtype)
        K = np.random.uniform(low, high, (seq_len, d_model)).astype(self.dtype)
        V = np.random.uniform(low, high, (seq_len, d_model)).astype(self.dtype)
        
        return {
            'Q': Q,
            'K': K,
            'V': V,
            'scale': scale,
            'seq_len': seq_len,
            'd_model': d_model
        }
    
    def generate_fixed_point_inputs(
        self,
        seq_len: int,
        d_model: int,
        int_bits: int = 4,
        frac_bits: int = 4
    ) -> dict:
        """
        Generate test data for fixed-point arithmetic (Q4.4 format).
        
        Args:
            seq_len, d_model: Dimensions
            int_bits: Number of integer bits
            frac_bits: Number of fractional bits
            
        Returns:
            dict with fixed-point Q, K, V
        """
        # Fixed-point range: [-2^(int_bits-1), 2^(int_bits-1) - 1] / 2^frac_bits
        max_val = (2 ** (int_bits - 1) - 1) / (2 ** frac_bits)
        min_val = -(2 ** (int_bits - 1)) / (2 ** frac_bits)
        
        Q = np.random.uniform(min_val, max_val, (seq_len, d_model)).astype(self.dtype)
        K = np.random.uniform(min_val, max_val, (seq_len, d_model)).astype(self.dtype)
        V = np.random.uniform(min_val, max_val, (seq_len, d_model)).astype(self.dtype)
        
        return {
            'Q': Q,
            'K': K,
            'V': V,
            'int_bits': int_bits,
            'frac_bits': frac_bits,
            'seq_len': seq_len,
            'd_model': d_model
        }
    
    def save_test_vectors(self, data: dict, filename: str):
        """Save test vectors to NPZ file for RTL simulation."""
        output_path = Path("../sim") / filename
        output_path.parent.mkdir(parents=True, exist_ok=True)
        
        # Convert to float64 for higher precision in storage
        data_f64 = {k: v.astype(np.float64) if isinstance(v, np.ndarray) else v 
                    for k, v in data.items()}
        
        np.savez_compressed(output_path, **data_f64)
        print(f"✓ Saved test vectors: {output_path}")
    
    def generate_golden_reference(
        self,
        Q: np.ndarray,
        K: np.ndarray,
        V: np.ndarray,
        scale: float
    ) -> np.ndarray:
        """
        Generate golden reference output using naive attention.
        
        Args:
            Q, K, V: Input matrices
            scale: Attention scaling factor
            
        Returns:
            Output matrix (N, d)
        """
        scores = Q @ K.T * scale
        scores_shifted = scores - np.max(scores, axis=-1, keepdims=True)
        attn_weights = np.exp(scores_shifted)
        attn_weights = attn_weights / np.sum(attn_weights, axis=-1, keepdims=True)
        output = attn_weights @ V
        
        return output.astype(self.dtype)


def generate_standard_test_suite():
    """
    Generate a standard test suite for RTL verification.
    Creates multiple test cases with different characteristics.
    """
    print("\n" + "=" * 70)
    print("Generating Standard Test Suite for RTL Verification")
    print("=" * 70 + "\n")
    
    test_cases = [
        {'name': 'tiny', 'seq_len': 8, 'd_model': 16, 'dtype': np.float32},
        {'name': 'small', 'seq_len': 32, 'd_model': 32, 'dtype': np.float32},
        {'name': 'medium', 'seq_len': 64, 'd_model': 64, 'dtype': np.float32},
        {'name': 'large', 'seq_len': 128, 'd_model': 128, 'dtype': np.float32},
    ]
    
    for i, config in enumerate(test_cases):
        print(f"Test {i+1}/{len(test_cases)}: {config['name']}")
        print(f"  Seq Len: {config['seq_len']}, D Model: {config['d_model']}")
        
        generator = TestDataGenerator(seed=42, dtype=config['dtype'])
        
        # Generate floating-point test vectors
        inputs_fp = generator.generate_attention_inputs(
            config['seq_len'],
            config['d_model']
        )
        
        # Generate reference output
        output = generator.generate_golden_reference(
            inputs_fp['Q'],
            inputs_fp['K'],
            inputs_fp['V'],
            inputs_fp['scale']
        )
        inputs_fp['output_golden'] = output
        
        # Save
        generator.save_test_vectors(inputs_fp, f"test_vectors_{config['name']}_fp32.npz")
        
        # Also generate fixed-point versions
        inputs_fp8 = generator.generate_fixed_point_inputs(
            config['seq_len'],
            config['d_model'],
            int_bits=4,
            frac_bits=4
        )
        inputs_fp8['output_golden'] = output  # Use same golden reference
        generator.save_test_vectors(inputs_fp8, f"test_vectors_{config['name']}_fp8.npz")
        
        print(f"  ✓ Generated FP32 and FP8 test vectors\n")
    
    print("=" * 70)
    print("Test Suite Generation Complete!")
    print("=" * 70 + "\n")


if __name__ == "__main__":
    generate_standard_test_suite()

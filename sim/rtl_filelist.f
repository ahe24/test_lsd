// =============================================================================
// rtl_filelist.f - order matters: packages first, then interfaces, then RTL
// =============================================================================

// -- common
../rtl/common/lsd_pkg.sv
../rtl/common/lsd_if.sv
../rtl/common/lsd_skid_buffer.sv
../rtl/common/lsd_fifo_sync.sv
../rtl/common/lsd_rr_arbiter.sv
../rtl/common/lsd_prbs_driver.sv
../rtl/common/lsd_self_traffic.sv
../rtl/common/lsd_heavy_compute.sv

// -- CNN
../rtl/cnn/mac/cnn_mac_int8_radix2.sv
../rtl/cnn/mac/cnn_mac_int8_booth4.sv
../rtl/cnn/mac/cnn_mac_int16_wallace.sv
../rtl/cnn/mac/cnn_mac_int16_systolic_cell.sv
../rtl/cnn/mac/cnn_mac_int16_systolic_array.sv
../rtl/cnn/mac/cnn_mac_fp32_ieee.sv
../rtl/cnn/mac/cnn_mac_bf16_approx.sv
../rtl/cnn/mac/cnn_mac_bitserial.sv

../rtl/cnn/activation/cnn_act_relu.sv
../rtl/cnn/activation/cnn_act_leaky_relu.sv
../rtl/cnn/activation/cnn_act_prelu.sv
../rtl/cnn/activation/cnn_act_sigmoid_plut.sv
../rtl/cnn/activation/cnn_act_tanh_cordic.sv
../rtl/cnn/activation/cnn_act_gelu_poly.sv
../rtl/cnn/activation/cnn_act_swish_hw.sv
../rtl/cnn/activation/cnn_act_mish_approx.sv
../rtl/cnn/activation/cnn_act_softmax_exp8.sv

../rtl/cnn/pooling/cnn_pool_max2x2.sv
../rtl/cnn/pooling/cnn_pool_max3x3.sv
../rtl/cnn/pooling/cnn_pool_avg2x2.sv
../rtl/cnn/pooling/cnn_pool_global_avg.sv

../rtl/cnn/conv/cnn_conv3x3_stride1.sv
../rtl/cnn/conv/cnn_conv5x5_stride1.sv
../rtl/cnn/conv/cnn_conv_dilated7x7.sv
../rtl/cnn/conv/cnn_conv_depthwise3x3.sv

../rtl/cnn/norm/cnn_norm_batch.sv
../rtl/cnn/norm/cnn_norm_layer.sv
../rtl/cnn/norm/cnn_norm_instance.sv

../rtl/cnn/top/cnn_tile_engine.sv
../rtl/cnn/top/cnn_top.sv

// -- Crypto
../rtl/crypto/aes256/aes_sbox_combinational.sv
../rtl/crypto/aes256/aes_subbytes.sv
../rtl/crypto/aes256/aes_shiftrows.sv
../rtl/crypto/aes256/aes_mixcolumns.sv
../rtl/crypto/aes256/aes_key_expand256.sv
../rtl/crypto/aes256/aes256_round.sv
../rtl/crypto/aes256/aes256_cipher.sv

../rtl/crypto/sha3/sha3_theta.sv
../rtl/crypto/sha3/sha3_rho_pi.sv
../rtl/crypto/sha3/sha3_chi.sv
../rtl/crypto/sha3/sha3_iota.sv
../rtl/crypto/sha3/sha3_round.sv
../rtl/crypto/sha3/sha3_keccak_f.sv

../rtl/crypto/rsa4096/rsa_adder_4096.sv
../rtl/crypto/rsa4096/rsa_subtractor_4096.sv
../rtl/crypto/rsa4096/rsa_montmul_4096.sv
../rtl/crypto/rsa4096/rsa_modexp_4096.sv

../rtl/crypto/ecc/ecc_fp_add256.sv
../rtl/crypto/ecc/ecc_fp_sub256.sv
../rtl/crypto/ecc/ecc_fp_mul256.sv
../rtl/crypto/ecc/ecc_point_double.sv
../rtl/crypto/ecc/ecc_point_add.sv
../rtl/crypto/ecc/ecc_scalar_mul.sv

../rtl/crypto/top/crypto_top.sv

// -- Graphics
../rtl/graphics/vertex/gfx_vec4_mul_mat4.sv
../rtl/graphics/vertex/gfx_vertex_transform.sv
../rtl/graphics/raster/gfx_edge_function.sv
../rtl/graphics/raster/gfx_barycentric.sv
../rtl/graphics/raster/gfx_tile_rasterizer.sv
../rtl/graphics/pixel/gfx_depth_test.sv
../rtl/graphics/pixel/gfx_blend_alpha.sv
../rtl/graphics/pixel/gfx_tex_bilinear.sv
../rtl/graphics/pixel/gfx_phong_shader.sv
../rtl/graphics/top/gfx_top.sv

// -- Complex ALU
../rtl/calu/fp/calu_fp_add.sv
../rtl/calu/fp/calu_fp_sub.sv
../rtl/calu/fp/calu_fp_mul.sv
../rtl/calu/fp/calu_fp_cordic_rot.sv
../rtl/calu/fft/calu_fft_butterfly_r2.sv
../rtl/calu/fft/calu_fft_butterfly_r4.sv
../rtl/calu/fft/calu_fft64_pipeline.sv
../rtl/calu/matrix/calu_mat_mul_8x8.sv
../rtl/calu/matrix/calu_mat_inv_8x8.sv
../rtl/calu/top/calu_top.sv

// -- ECC codecs
../rtl/eccd/ldpc/ldpc_cnode_minsum.sv
../rtl/eccd/ldpc/ldpc_vnode.sv
../rtl/eccd/ldpc/ldpc_decoder_648.sv
../rtl/eccd/turbo/turbo_interleaver.sv
../rtl/eccd/turbo/turbo_siso_decoder.sv
../rtl/eccd/turbo/turbo_decoder_top.sv
../rtl/eccd/top/eccd_top.sv

// -- Top-level integration
//    Phase 3 layout: five functional subsystem islands + eight heavy-
//    compute islands.  The previous bloat farms (rtl/gen/<family>/) and
//    their wrapper lsd_bloat_islands.sv have been retired — they were
//    excellent for compile-time stress (thousands of unique modules) but
//    qopt -O5 optimised them down to ~0% per-cycle simulator work.  See
//    rtl/common/lsd_heavy_compute.sv + rtl/top/lsd_compute_islands.sv
//    for the replacement.
../rtl/top/lsd_interconnect.sv
../rtl/top/lsd_stream_fanout.sv
../rtl/top/lsd_stream_merge.sv
../rtl/top/lsd_subsys_islands.sv
../rtl/top/lsd_compute_islands.sv
../rtl/top/lsd_top.sv

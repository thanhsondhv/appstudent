# File: services/metadata_service.py

SQL_METADATA = {
    "DiemHocPhan": {
        "description": "Bảng chứa điểm tổng kết các môn học của sinh viên.",
        "logic_nghiep_vu": "Điểm hệ 10 lưu ở cột 'Diem'. Nếu Diem < 4.0 là TRƯỢT/NỢ MÔN. Luôn kèm điều kiện d.IsDeleted = 0.",
        "joins": "Nối với bảng 'tbl_HocPhan' qua: DiemHocPhan.IdHocPhan = tbl_HocPhan.InstanceId (GUID)."
    },
    
    "tbl_HocPhan": {
        "description": "Bảng danh mục môn học toàn trường.",
        "columns": "Id (INT dùng nối Khung), InstanceId (GUID dùng nối bảng Điểm), Code (Mã học phần), Ten (Tên môn học).",
        "role": "Cầu nối giữa Khung đào tạo (Id) và bảng Điểm (InstanceId)."
    },
    
    "tbl_ChuongTrinhDaoTao_HocPhan": {
        "description": "Bảng khung chương trình đào tạo của từng ngành.",
        "logic_nghiep_vu": "IdChuongTrinhDaoTao là mã ID số nguyên {program_code}. PhanKy là học kỳ dự kiến.",
        "joins": "Nối với 'tbl_HocPhan' qua: tbl_ChuongTrinhDaoTao_HocPhan.IdHocPhan = tbl_HocPhan.Id (INT)."
    },

    "QUY_TAC_SQL_BAT_BUOC": {
        "GPA": "Dùng biến {gpa} có sẵn, KHÔNG viết SQL tính lại.",
        "NO_MON": "Dùng HAVING MAX(Diem) < 4.0 để lọc những môn thi nhiều lần vẫn trượt.",
        "MON_CHUA_HOC": "Dùng LEFT JOIN giữa tbl_ChuongTrinhDaoTao_HocPhan và bảng điểm của SV, lọc d.Diem IS NULL.",
        "ID_SINH_VIEN": "Luôn dùng (RTRIM(IdNguoiHoc) = '{student_id}' OR RTRIM(IdNguoiHoc) = 'SV{student_id}')"
    }
}
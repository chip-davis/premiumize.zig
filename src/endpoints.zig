//! Every Premiumize API path, relative to `Options.base_url`.

pub const account = struct {
    pub const info = "/account/info";
};

pub const folder = struct {
    pub const list = "/folder/list";
    pub const create = "/folder/create";
    pub const rename = "/folder/rename";
    pub const paste = "/folder/paste";
    pub const delete = "/folder/delete";
    pub const uploadinfo = "/folder/uploadinfo";
    pub const search = "/folder/search";
};

pub const item = struct {
    pub const details = "/item/details";
};
